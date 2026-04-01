import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:psygo/utils/macos_enter_ime_guard.dart';

void main() {
  group('MacOsEnterImeGuard', () {
    test('stays idle without composition', () {
      final guard = MacOsEnterImeGuard();

      guard.updateEditingValue(
        const TextEditingValue(
          text: 'hello',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      expect(guard.state, MacOsEnterImeGuardState.idle);
      expect(guard.shouldDeferEnter(isMacOS: true), isFalse);
    });

    test('defers enter while composing', () {
      final guard = MacOsEnterImeGuard();

      guard.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );

      expect(guard.state, MacOsEnterImeGuardState.composing);
      expect(guard.shouldDeferEnter(isMacOS: true), isTrue);
    });

    test('defers first enter after composition commits', () {
      final guard = MacOsEnterImeGuard();

      guard.updateEditingValue(
        const TextEditingValue(
          text: 'ni',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      guard.consumeDeferredEnter();
      guard.updateEditingValue(
        const TextEditingValue(
          text: '你',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange.empty,
        ),
      );

      expect(guard.state, MacOsEnterImeGuardState.idle);
      expect(guard.shouldDeferEnter(isMacOS: true), isFalse);
    });

    test('defers committed composition until enter is consumed', () {
      final guard = MacOsEnterImeGuard();

      guard.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      guard.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange.empty,
        ),
      );

      expect(
        guard.state,
        MacOsEnterImeGuardState.committedAwaitingEnter,
      );
      expect(guard.shouldDeferEnter(isMacOS: true), isTrue);

      guard.consumeDeferredEnter();

      expect(guard.state, MacOsEnterImeGuardState.idle);
      expect(guard.shouldDeferEnter(isMacOS: true), isFalse);
      expect(guard.shouldDeferEnter(isMacOS: false), isFalse);
    });
  });
}
