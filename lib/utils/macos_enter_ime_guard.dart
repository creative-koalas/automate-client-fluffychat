import 'package:flutter/services.dart';

enum MacOsEnterImeGuardState {
  idle,
  composing,
  committedAwaitingEnter,
}

class MacOsEnterImeGuard {
  MacOsEnterImeGuardState _state = MacOsEnterImeGuardState.idle;

  MacOsEnterImeGuardState get state => _state;

  void updateEditingValue(TextEditingValue value) {
    final hasActiveComposition =
        value.composing.isValid && !value.composing.isCollapsed;

    if (hasActiveComposition) {
      _state = MacOsEnterImeGuardState.composing;
      return;
    }

    if (_state == MacOsEnterImeGuardState.composing) {
      _state = MacOsEnterImeGuardState.committedAwaitingEnter;
    }
  }

  bool shouldDeferEnter({required bool isMacOS}) {
    if (!isMacOS) return false;
    return _state != MacOsEnterImeGuardState.idle;
  }

  void consumeDeferredEnter() {
    if (_state != MacOsEnterImeGuardState.idle) {
      _state = MacOsEnterImeGuardState.idle;
    }
  }

  void reset() {
    _state = MacOsEnterImeGuardState.idle;
  }
}
