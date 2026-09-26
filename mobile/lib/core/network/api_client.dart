import 'package:dio/dio.dart';
import 'api_endpoints.dart';
import 'auth_interceptor.dart';
import '../storage/secure_storage.dart';
import '../errors/app_exception.dart';

class ApiClient {
  late final Dio _dio;
  final SecureStorageService storage;

  ApiClient({
    required this.storage,
    String? baseUrl,
    void Function()? onUnauthorized,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiEndpoints.defaultBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      AuthInterceptor(storage: storage, onUnauthorized: onUnauthorized),
      LogInterceptor(
        request: true,
        requestHeader: false,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ),
    ]);
  }

  void updateBaseUrl(String newBaseUrl) {
    _dio.options.baseUrl = newBaseUrl;
  }

  String get currentBaseUrl => _dio.options.baseUrl;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get<T>(path, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleDioError(e, isMutation: false);
    }
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post<T>(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleDioError(e, isMutation: true);
    }
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put<T>(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleDioError(e, isMutation: true);
    }
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete<T>(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleDioError(e, isMutation: true);
    }
  }

  AppException _handleDioError(DioException error, {bool isMutation = false}) {
    if (error.error is AppException) {
      return error.error as AppException;
    }

    final isConnectionError = error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError;

    // Section 36: Offline Behavior for Inventory Mutations
    if (isConnectionError) {
      if (isMutation) {
        return OfflineException(
          title: 'No Internet Connection',
          message: 'Inventory changes require a connection.',
        );
      }
      return NetworkException(
        message: 'Unable to reach the StockSense server. Check your connection.',
      );
    }

    final statusCode = error.response?.statusCode;
    final data = error.response?.data;
    String cleanMessage = _extractCleanErrorMessage(data, statusCode);

    switch (statusCode) {
      case 401:
        return UnauthorizedException(message: cleanMessage);
      case 403:
        return ForbiddenException(message: cleanMessage);
      case 404:
        return NotFoundException(message: cleanMessage);
      case 409:
        return ConflictException(message: cleanMessage);
      case 422:
        return ValidationException(message: cleanMessage, details: data);
      case 500:
        return ServerException(message: 'Server error occurred. Please try again later.');
      default:
        return AppException(
          message: cleanMessage,
          statusCode: statusCode,
          details: data,
        );
    }
  }

  String _extractCleanErrorMessage(dynamic data, int? statusCode) {
    String message = '';
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        // Handle FastAPI validation error array: [{'loc': [...], 'msg': '...', 'type': '...'}]
        final msgs = detail.map((e) {
          if (e is Map<String, dynamic>) {
            final field = (e['loc'] as List?)?.lastOrNull?.toString() ?? 'Field';
            final msg = e['msg']?.toString() ?? 'is invalid';
            return '$field: $msg';
          }
          return e.toString();
        }).join(', ');
        message = msgs;
      } else if (data['message'] is String) {
        message = data['message'];
      }
    } else if (data is String) {
      message = data;
    }

    // Section 35: Never expose raw database exceptions
    final rawLower = message.toLowerCase();
    if (rawLower.contains('psycopg2') ||
        rawLower.contains('sqlite3') ||
        rawLower.contains('sqlalchemy') ||
        rawLower.contains('operationalerror') ||
        rawLower.contains('integrityerror') ||
        rawLower.contains('traceback') ||
        rawLower.contains('syntax error') ||
        rawLower.contains('table') && rawLower.contains('column')) {
      if (statusCode != null && statusCode >= 500) {
        return 'A database error occurred. Please contact your system administrator.';
      }
      return 'The requested operation could not be completed due to a database constraint.';
    }

    if (message.isEmpty) {
      if (statusCode == 401) return 'Session expired or unauthorized. Please log in again.';
      if (statusCode == 403) return 'Access forbidden. You do not have permission for this action.';
      if (statusCode == 404) return 'Requested record or resource was not found.';
      if (statusCode == 409) return 'Operation conflict. The requested item state has changed.';
      if (statusCode == 422) return 'Validation error. Please verify the provided details.';
      if (statusCode != null && statusCode >= 500) return 'Server error occurred. Please try again later.';
      return 'An unexpected error occurred.';
    }

    return message;
  }
}
