import 'package:psygo/services/onboarding_guide_service.dart';

class ChatRoomGuideService {
  ChatRoomGuideService._();

  static final ChatRoomGuideService instance = ChatRoomGuideService._();

  Future<bool> shouldShowGuide({
    required String? userId,
    required String? roomId,
  }) async {
    final state = await OnboardingGuideService.instance.getState(userId);
    if (state == null) {
      return false;
    }
    return !state.employeeChatRoom;
  }

  Future<void> markGuideCompleted({
    required String? userId,
    required String? roomId,
  }) async {
    await OnboardingGuideService.instance.updateState(
      userId,
      employeeChatRoom: true,
    );
  }

  Future<bool> shouldShowGroupMentionGuide({
    required String? userId,
    required String? roomId,
  }) async {
    final state = await OnboardingGuideService.instance.getState(userId);
    if (state == null) {
      return false;
    }
    return !state.groupChat;
  }

  Future<void> markGroupMentionGuideCompleted({
    required String? userId,
    required String? roomId,
  }) async {
    await OnboardingGuideService.instance.updateState(
      userId,
      groupChat: true,
    );
  }
}
