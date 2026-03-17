import 'package:flutter_test/flutter_test.dart';
import 'package:psygo/models/announcement.dart';

void main() {
  test('Announcement parses defaults correctly', () {
    final announcement = Announcement.fromJson({
      'announcement_id': 'ann_1',
      'title': 'Title',
      'body': 'Body',
    });

    expect(announcement.maxImpressions, 3);
    expect(announcement.minIntervalHours, 0);
    expect(announcement.targetPlatforms, const ['all']);
    expect(announcement.supportsScene('chat_list'), isTrue);
  });

  test('Announcement platform matching works with target_platforms', () {
    final announcement = Announcement.fromJson({
      'announcement_id': 'ann_android',
      'title': 'Android only',
      'body': 'Body',
      'target_platforms': ['android'],
    });

    expect(announcement.matchesPlatform('android'), isTrue);
    expect(announcement.matchesPlatform('ios'), isFalse);
  });

  test('Announcement active window respects start/end timestamps', () {
    final announcement = Announcement.fromJson({
      'announcement_id': 'ann_window',
      'title': 'Window',
      'body': 'Body',
      'start_at': '2026-03-01T00:00:00Z',
      'end_at': '2026-03-31T00:00:00Z',
    });

    expect(announcement.isActiveAt(DateTime.parse('2026-03-15T12:00:00Z')), true);
    expect(announcement.isActiveAt(DateTime.parse('2026-04-01T00:00:00Z')), false);
  });
}
