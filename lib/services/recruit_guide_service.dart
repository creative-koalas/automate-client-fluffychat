import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RecruitGuideService {
  RecruitGuideService._();

  static final RecruitGuideService instance = RecruitGuideService._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keyPrefix = 'automate_recruit_guide_completed_v1_';
  static const bool debugAlwaysShowGuide = false;

  Future<bool> shouldShowGuide(String? userId) async {
    if (debugAlwaysShowGuide) {
      return true;
    }

    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return false;
    }
    final completed = await _storage.read(
      key: '$_keyPrefix$normalizedUserId',
    );
    return completed?.toLowerCase() != 'true';
  }

  Future<void> markGuideCompleted(String? userId) async {
    if (debugAlwaysShowGuide) {
      return;
    }

    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return;
    }
    await _storage.write(
      key: '$_keyPrefix$normalizedUserId',
      value: 'true',
    );
  }
}
