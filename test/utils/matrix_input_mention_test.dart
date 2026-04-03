import 'package:flutter_test/flutter_test.dart';
import 'package:psygo/utils/input_mention_query.dart';

void main() {
  group('findActiveInputMentionQuery', () {
    test('matches a plain at trigger at the start of the input', () {
      final query = findActiveInputMentionQuery(text: '@', cursorOffset: 1);

      expect(query, isNotNull);
      expect(query?.start, 0);
      expect(query?.token, '@');
      expect(query?.query, isEmpty);
    });

    test('matches mentions after chinese text without a space', () {
      final text = '你好@张';
      final query = findActiveInputMentionQuery(
        text: text,
        cursorOffset: text.length,
      );

      expect(query, isNotNull);
      expect(query?.start, text.indexOf('@'));
      expect(query?.token, '@张');
      expect(query?.query, '张');
    });

    test('matches full-width chinese input method at triggers', () {
      final text = '你好＠张';
      final query = findActiveInputMentionQuery(
        text: text,
        cursorOffset: text.length,
      );

      expect(query, isNotNull);
      expect(query?.start, text.indexOf('＠'));
      expect(query?.token, '＠张');
      expect(query?.query, '张');
    });

    test('matches mentions after english text without a space', () {
      const text = 'hello@al';
      final query = findActiveInputMentionQuery(
        text: text,
        cursorOffset: text.length,
      );

      expect(query, isNotNull);
      expect(query?.start, text.indexOf('@'));
      expect(query?.token, '@al');
      expect(query?.query, 'al');
    });

    test('matches mentions after whitespace', () {
      const text = 'hello @alice';
      final query = findActiveInputMentionQuery(
        text: text,
        cursorOffset: text.length,
      );

      expect(query, isNotNull);
      expect(query?.token, '@alice');
      expect(query?.query, 'alice');
    });

    test('returns null once punctuation terminates the mention token', () {
      const text = 'hello@alice,';
      final query = findActiveInputMentionQuery(
        text: text,
        cursorOffset: text.length,
      );

      expect(query, isNull);
    });

    test('tracks the last active at trigger before the cursor', () {
      const text = 'hello@alice @bo';
      final query = findActiveInputMentionQuery(
        text: text,
        cursorOffset: text.length,
      );

      expect(query, isNotNull);
      expect(query?.token, '@bo');
      expect(query?.query, 'bo');
    });
  });

  group('findWholeInputMentionDeleteRange', () {
    test('deletes the whole mention when backspacing at mention end', () {
      const text = 'hello @alice';
      final range = findWholeInputMentionDeleteRange(
        text: text,
        cursorOffset: text.length,
        mentionTokens: const ['@alice'],
      );

      expect(range, isNotNull);
      expect(range?.start, 5);
      expect(range?.end, text.length);
      expect(text.replaceRange(range!.start, range.end, ''), 'hello');
    });

    test('deletes the whole mention when backspacing the trailing space', () {
      const text = 'hello @alice ';
      final range = findWholeInputMentionDeleteRange(
        text: text,
        cursorOffset: text.length,
        mentionTokens: const ['@alice'],
      );

      expect(range, isNotNull);
      expect(range?.start, 5);
      expect(range?.end, text.length);
      expect(text.replaceRange(range!.start, range.end, ''), 'hello');
    });

    test('keeps user-typed whitespace before the mention intact', () {
      const text = 'hello  @alice ';
      final range = findWholeInputMentionDeleteRange(
        text: text,
        cursorOffset: text.length,
        mentionTokens: const ['@alice'],
      );

      expect(range, isNotNull);
      expect(range?.start, 7);
      expect(range?.end, text.length);
      expect(text.replaceRange(range!.start, range.end, ''), 'hello  ');
    });
  });
}
