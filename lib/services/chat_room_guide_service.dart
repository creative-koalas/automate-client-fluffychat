import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ChatRoomGuideService {
  ChatRoomGuideService._();

  static final ChatRoomGuideService instance = ChatRoomGuideService._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _directGuideKeyPrefix =
      'automate_chat_room_guide_completed_v2_';
  static const String _groupMentionGuideKeyPrefix =
      'automate_group_chat_mention_guide_completed_v2_';
  static const bool debugAlwaysShowDirectGuide = false;
  static const bool debugAlwaysShowGroupMentionGuide = false;

  Future<bool> shouldShowGuide({
    required String? userId,
    required String? roomId,
  }) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return false;
    }

    if (debugAlwaysShowDirectGuide) {
      return true;
    }

    return _shouldShowByKey(
      key: '$_directGuideKeyPrefix$normalizedUserId',
    );
  }

  Future<void> markGuideCompleted({
    required String? userId,
    required String? roomId,
  }) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return;
    }

    if (debugAlwaysShowDirectGuide) {
      return;
    }

    await _markGuideCompletedByKey(
      key: '$_directGuideKeyPrefix$normalizedUserId',
    );
  }

  Future<bool> shouldShowGroupMentionGuide({
    required String? userId,
    required String? roomId,
  }) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return false;
    }

    if (debugAlwaysShowGroupMentionGuide) {
      return true;
    }

    return _shouldShowByKey(
      key: '$_groupMentionGuideKeyPrefix$normalizedUserId',
    );
  }

  Future<void> markGroupMentionGuideCompleted({
    required String? userId,
    required String? roomId,
  }) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return;
    }

    if (debugAlwaysShowGroupMentionGuide) {
      return;
    }

    await _markGuideCompletedByKey(
      key: '$_groupMentionGuideKeyPrefix$normalizedUserId',
    );
  }

  Future<bool> _shouldShowByKey({required String key}) async {
    final completed = await _storage.read(
      key: key,
    );
    return completed?.toLowerCase() != 'true';
  }

  Future<void> _markGuideCompletedByKey({required String key}) async {
    await _storage.write(
      key: key,
      value: 'true',
    );
  }
}
