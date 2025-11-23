import 'dart:async';

/// Centralized auth state for Automate features.
class AutomateAuthManager {
  AutomateAuthManager._();
  static final AutomateAuthManager instance = AutomateAuthManager._();

  final StreamController<void> _unauthorizedController =
      StreamController<void>.broadcast();

  Stream<void> get unauthorized => _unauthorizedController.stream;

  void notifyUnauthorized() {
    if (!_unauthorizedController.isClosed) {
      _unauthorizedController.add(null);
    }
  }

  Future<void> dispose() async {
    await _unauthorizedController.close();
  }
}
