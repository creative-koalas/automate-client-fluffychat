class AutomateBackendException implements Exception {
  final String message;
  final int? statusCode;

  AutomateBackendException(this.message, {this.statusCode});

  @override
  String toString() => 'AutomateBackendException: $message';
}

class UnauthorizedException extends AutomateBackendException {
  UnauthorizedException({String message = 'Unauthorized'})
      : super(message, statusCode: 401);
}
