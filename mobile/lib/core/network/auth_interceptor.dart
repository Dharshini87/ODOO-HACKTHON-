import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';
import '../errors/app_exception.dart';

class AuthInterceptor extends Interceptor {
  final SecureStorageService storage;
  final void Function()? onUnauthorized;

  AuthInterceptor({
    required this.storage,
    this.onUnauthorized,
  });

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await storage.getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    options.headers['Accept'] = 'application/json';
    options.headers['Content-Type'] = 'application/json';

    // Section 40: Attach Idempotency-Key for mutation requests
    final method = options.method.toUpperCase();
    if (['POST', 'PUT', 'PATCH', 'DELETE'].contains(method)) {
      options.headers['Idempotency-Key'] ??=
          'ss-${DateTime.now().microsecondsSinceEpoch}-${options.path.hashCode.abs()}';
    }

    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      onUnauthorized?.call();
      return handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          error: UnauthorizedException(),
          type: err.type,
        ),
      );
    }

    final data = err.response?.data;
    String errorMessage = 'An unexpected error occurred';
    if (data is Map && data.containsKey('detail')) {
      final detail = data['detail'];
      if (detail is String) {
        errorMessage = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final first = detail[0];
        if (first is Map && first.containsKey('msg')) {
          errorMessage = first['msg'].toString();
        } else {
          errorMessage = detail.toString();
        }
      }
    }

    if (errorMessage.toLowerCase().contains('insufficient stock')) {
      return handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          error: InsufficientStockException(message: errorMessage),
          type: err.type,
        ),
      );
    }

    return handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        error: AppException(
          message: errorMessage,
          statusCode: err.response?.statusCode,
          details: data,
        ),
        type: err.type,
      ),
    );
  }
}
