import 'dart:async';

import 'package:flutter/services.dart';

typedef ClipboardTextReader = Future<String?> Function();
typedef ComposerValueReader = TextEditingValue Function();
typedef ComposerValueWriter = void Function(TextEditingValue value);

class MacOsVoiceInputClipboardBridge {
  MacOsVoiceInputClipboardBridge({
    required ClipboardTextReader readClipboardText,
    required ComposerValueReader readComposerValue,
    required ComposerValueWriter writeComposerValue,
    this.pollInterval = const Duration(milliseconds: 500),
  })  : _readClipboardText = readClipboardText,
        _readComposerValue = readComposerValue,
        _writeComposerValue = writeComposerValue;

  final ClipboardTextReader _readClipboardText;
  final ComposerValueReader _readComposerValue;
  final ComposerValueWriter _writeComposerValue;
  final Duration pollInterval;

  Timer? _pollTimer;
  String? _lastObservedClipboardText;
  bool _primed = false;

  bool get isRunning => _pollTimer != null;

  void start() {
    stop();
    _primed = false;
    _lastObservedClipboardText = null;
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(poll()));
    unawaited(poll());
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _primed = false;
    _lastObservedClipboardText = null;
  }

  Future<void> poll() async {
    final clipboardText = await _safeReadClipboardText();
    if (!_primed) {
      _primed = true;
      _lastObservedClipboardText = clipboardText;
      return;
    }

    if (clipboardText == null ||
        clipboardText.isEmpty ||
        clipboardText == _lastObservedClipboardText) {
      return;
    }
    _lastObservedClipboardText = clipboardText;

    final currentValue = _readComposerValue();
    if (currentValue.text.isNotEmpty) {
      return;
    }

    final selection = currentValue.selection;
    final baseOffset = selection.isValid
        ? selection.start.clamp(0, currentValue.text.length)
        : 0;
    final extentOffset = selection.isValid
        ? selection.end.clamp(0, currentValue.text.length)
        : 0;
    final nextText = currentValue.text.replaceRange(
      baseOffset,
      extentOffset,
      clipboardText,
    );
    final nextOffset = baseOffset + clipboardText.length;
    _writeComposerValue(
      TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextOffset),
      ),
    );
  }

  Future<String?> _safeReadClipboardText() async {
    try {
      return await _readClipboardText();
    } catch (_) {
      return null;
    }
  }
}
