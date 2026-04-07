import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psygo/utils/macos_voice_input_clipboard_bridge.dart';

void main() {
  group('MacOsVoiceInputClipboardBridge', () {
    test('primes on first poll without mutating composer', () async {
      var clipboardText = 'first result';
      var composerValue = const TextEditingValue();
      final bridge = MacOsVoiceInputClipboardBridge(
        readClipboardText: () async => clipboardText,
        readComposerValue: () => composerValue,
        writeComposerValue: (value) => composerValue = value,
      );

      await bridge.poll();

      expect(composerValue.text, isEmpty);
    });

    test('inserts new clipboard text after priming when composer is empty',
        () async {
      var clipboardText = 'first result';
      var composerValue = const TextEditingValue();
      final bridge = MacOsVoiceInputClipboardBridge(
        readClipboardText: () async => clipboardText,
        readComposerValue: () => composerValue,
        writeComposerValue: (value) => composerValue = value,
      );

      await bridge.poll();
      clipboardText = 'voice dictated sentence';

      await bridge.poll();

      expect(composerValue.text, 'voice dictated sentence');
      expect(
          composerValue.selection.baseOffset, 'voice dictated sentence'.length);
    });

    test('does not overwrite composer text after priming', () async {
      var clipboardText = 'first result';
      var composerValue = const TextEditingValue();
      final bridge = MacOsVoiceInputClipboardBridge(
        readClipboardText: () async => clipboardText,
        readComposerValue: () => composerValue,
        writeComposerValue: (value) => composerValue = value,
      );

      await bridge.poll();
      composerValue = const TextEditingValue(
        text: 'keep existing text',
        selection: TextSelection.collapsed(offset: 18),
      );
      clipboardText = 'voice dictated sentence';

      await bridge.poll();

      expect(composerValue.text, 'keep existing text');
    });
  });
}
