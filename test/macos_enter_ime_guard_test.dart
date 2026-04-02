import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psygo/utils/macos_enter_ime_guard.dart';

void main() {
  group('MacOsEnterImeGuard', () {
    test('does not defer without active composition', () {
      final guard = MacOsEnterImeGuard();

      final handled = guard.markSubmitToSkipIfComposing(
        const TextEditingValue(
          text: 'hello',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange.empty,
        ),
      );

      expect(handled, isFalse);
      expect(guard.consumeSkippedSubmit(), isFalse);
    });

    test('defers exactly one submit when enter confirms composition', () {
      final guard = MacOsEnterImeGuard();

      final handled = guard.markSubmitToSkipIfComposing(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );

      expect(handled, isTrue);
      expect(guard.consumeSkippedSubmit(), isTrue);
      expect(guard.consumeSkippedSubmit(), isFalse);
    });

    test('does not keep swallowing the next normal enter after ime commit', () {
      final guard = MacOsEnterImeGuard();

      guard.markSubmitToSkipIfComposing(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );

      expect(guard.consumeSkippedSubmit(), isTrue);

      final handled = guard.markSubmitToSkipIfComposing(
        const TextEditingValue(
          text: '你',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange.empty,
        ),
      );

      expect(handled, isFalse);
      expect(guard.consumeSkippedSubmit(), isFalse);
    });

    test('reset clears pending skipped submit', () {
      final guard = MacOsEnterImeGuard();

      final handled = guard.markSubmitToSkipIfComposing(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );

      expect(handled, isTrue);

      guard.reset();

      expect(guard.consumeSkippedSubmit(), isFalse);
    });
  });
}
