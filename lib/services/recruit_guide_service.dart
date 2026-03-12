import 'package:psygo/services/onboarding_guide_service.dart';

class RecruitGuideService {
  RecruitGuideService._();

  static final RecruitGuideService instance = RecruitGuideService._();

  Future<bool> shouldShowGuide(String? userId) async {
    final state = await OnboardingGuideService.instance.getState(userId);
    if (state == null) {
      return false;
    }
    return !state.recruit;
  }

  Future<void> markGuideCompleted(String? userId) async {
    await OnboardingGuideService.instance.updateState(
      userId,
      recruit: true,
    );
  }
}
