import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class MacOsEnterImeGuard {
  static final RegExp _latinImePreeditPattern =
      RegExp(r"^[a-zA-Z0-9'`\-\s]+$");
  bool _skipNextSubmit = false;

  bool markSubmitToSkipIfComposing(TextEditingValue value) {
    final hasActiveComposition =
        value.composing.isValid && !value.composing.isCollapsed;
    if (!hasActiveComposition) {
      return false;
    }

    final composingText = value.composing.textInside(value.text).trim();
    if (composingText.isEmpty) {
      debugPrint(
        '[MacOsEnterImeGuard] composing active but empty text; allow submit. '
        'range=${value.composing.start}-${value.composing.end}',
      );
      return false;
    }

    // Only swallow Enter for classic IME preedit states such as pinyin or
    // zhuyin romanization. Third-party voice input tools may keep a composing
    // range around already-finalized CJK text; those should still submit.
    final looksLikeLatinPreedit =
        _latinImePreeditPattern.hasMatch(composingText);
    debugPrint(
      '[MacOsEnterImeGuard] composing="$composingText" '
      'len=${composingText.length} '
      'range=${value.composing.start}-${value.composing.end} '
      'looksLikeLatinPreedit=$looksLikeLatinPreedit '
      'fullText="${value.text}"',
    );
    if (!looksLikeLatinPreedit) {
      return false;
    }

    _skipNextSubmit = true;
    debugPrint(
      '[MacOsEnterImeGuard] swallowing Enter to avoid premature IME submit',
    );
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
