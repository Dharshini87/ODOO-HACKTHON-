class AppException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;
  final String? title;

  AppException({
    required this.message,
    this.statusCode,
    this.details,
    this.title,
  });

  @override
  String toString() => message;
}

// 401 Unauthorized
class UnauthorizedException extends AppException {
  UnauthorizedException({super.message = 'Session expired or unauthorized. Please log in again.'})
      : super(statusCode: 401, title: 'Unauthorized');
}

// 403 Forbidden
class ForbiddenException extends AppException {
  ForbiddenException({super.message = 'Access forbidden. You do not have permission for this action.'})
      : super(statusCode: 403, title: 'Forbidden');
}

// 404 Not Found
class NotFoundException extends AppException {
  NotFoundException({super.message = 'Requested record or resource was not found.'})
      : super(statusCode: 404, title: 'Not Found');
}

// 409 Conflict
class ConflictException extends AppException {
  ConflictException({super.message = 'Operation conflict. The requested item state has changed.'})
      : super(statusCode: 409, title: 'Conflict');
}

// 422 Validation Error
class ValidationException extends AppException {
  ValidationException({super.message = 'Validation error. Please verify the provided details.', super.details})
      : super(statusCode: 422, title: 'Validation Error');
}

// 500 Server Error
class ServerException extends AppException {
  ServerException({super.message = 'Server error occurred. Please try again later.'})
      : super(statusCode: 500, title: 'Server Error');
}

// Section 36: Offline Behavior
class OfflineException extends AppException {
  OfflineException({
    super.message = 'Inventory changes require a connection.',
    super.title = 'No Internet Connection',
  }) : super(statusCode: 0);
}

class NetworkException extends AppException {
  NetworkException({super.message = 'Unable to reach the StockSense server. Check your connection.'})
      : super(title: 'Network Error');
}

class InsufficientStockException extends AppException {
  final double? available;
  final double? requested;

  InsufficientStockException({
    required super.message,
    this.available,
    this.requested,
  }) : super(statusCode: 400, title: 'Insufficient Stock');
}
