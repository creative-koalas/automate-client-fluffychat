import 'package:flutter/services.dart';

class MacOsEnterImeGuard {
  bool _skipNextSubmit = false;

  bool markSubmitToSkipIfComposing(TextEditingValue value) {
    final hasActiveComposition =
        value.composing.isValid && !value.composing.isCollapsed;
    if (!hasActiveComposition) {
      return false;
    }
    _skipNextSubmit = true;
    return true;
  }

  bool consumeSkippedSubmit() {
    if (!_skipNextSubmit) {
      return false;
    }
    _skipNextSubmit = false;
    return true;
  }

  void reset() {
    _skipNextSubmit = false;
  }
}
