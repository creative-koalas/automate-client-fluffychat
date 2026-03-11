import 'package:psygo/services/onboarding_guide_service.dart';

class EmployeeWorkTemplateVisibilityService {
  EmployeeWorkTemplateVisibilityService._();

  static final EmployeeWorkTemplateVisibilityService instance =
      EmployeeWorkTemplateVisibilityService._();

  final Map<String, bool> _memoryCache = {};

  Future<bool> isDismissed(String? userId) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return false;
    }

    final cached = _memoryCache[normalizedUserId];
    if (cached != null) {
      return cached;
    }

    final state =
        await OnboardingGuideService.instance.getState(normalizedUserId);
    final dismissed = state?.employeeWorkTemplateDismissed ?? false;
    _memoryCache[normalizedUserId] = dismissed;
    return dismissed;
  }

  Future<void> markDismissed(String? userId) async {
    final normalizedUserId = userId?.trim() ?? '';
    if (normalizedUserId.isEmpty) {
      return;
    }

    _memoryCache[normalizedUserId] = true;
    final updated = await OnboardingGuideService.instance.updateState(
      normalizedUserId,
      employeeWorkTemplateDismissed: true,
    );
    if (updated != null) {
      _memoryCache[normalizedUserId] = updated.employeeWorkTemplateDismissed;
    }
  }
}
