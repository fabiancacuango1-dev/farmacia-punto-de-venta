/// Custom exception hierarchy for the application
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'AppException($code): $message';
}

class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.code, super.originalError});
}

class AuthException extends AppException {
  const AuthException(super.message, {super.code, super.originalError});
}

class ValidationException extends AppException {
  final Map<String, String> fieldErrors;
  const ValidationException(super.message, {this.fieldErrors = const {}, super.code});
}

class SyncException extends AppException {
  const SyncException(super.message, {super.code, super.originalError});
}

class NetworkException extends AppException {
  final int? statusCode;
  const NetworkException(super.message, {this.statusCode, super.code, super.originalError});
}

class InsufficientStockException extends AppException {
  final String productName;
  final double available;
  final double requested;

  const InsufficientStockException({
    required this.productName,
    required this.available,
    required this.requested,
  }) : super('Stock insuficiente para $productName');
}
