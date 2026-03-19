import 'package:flutter_test/flutter_test.dart';

class PsygoSmsTestCredentials {
  static const String phoneDefine = 'PSYGO_UI_TEST_PHONE';
  static const String codeDefine = 'PSYGO_UI_TEST_CODE';

  final String phone;
  final String? code;

  const PsygoSmsTestCredentials({
    required this.phone,
    this.code,
  });

  bool get hasCode => code != null && code!.isNotEmpty;

  static PsygoSmsTestCredentials fromEnvironmentOrDefaults({
    required String defaultPhone,
    String? defaultCode,
  }) {
    const phoneOverride = String.fromEnvironment(phoneDefine);
    const codeOverride = String.fromEnvironment(codeDefine);

    if (phoneOverride.isNotEmpty) {
      return PsygoSmsTestCredentials(
        phone: phoneOverride,
        code: codeOverride.isNotEmpty ? codeOverride : null,
      );
    }

    return PsygoSmsTestCredentials(
      phone: defaultPhone,
      code: (defaultCode != null && defaultCode.isNotEmpty) ? defaultCode : null,
    );
  }

  static PsygoSmsTestCredentials? maybeFromEnvironment({
    bool requireCode = false,
  }) {
    const phoneOverride = String.fromEnvironment(phoneDefine);
    const codeOverride = String.fromEnvironment(codeDefine);
    if (phoneOverride.isEmpty) return null;
    if (requireCode && codeOverride.isEmpty) return null;
    return PsygoSmsTestCredentials(
      phone: phoneOverride,
      code: codeOverride.isNotEmpty ? codeOverride : null,
    );
  }

  static String? missingReason({
    bool requireCode = false,
  }) {
    const phoneOverride = String.fromEnvironment(phoneDefine);
    const codeOverride = String.fromEnvironment(codeDefine);
    if (phoneOverride.isEmpty) {
      return 'Missing SMS login test phone parameter. Pass '
          '--dart-define=$phoneDefine=<phone>.';
    }
    if (!requireCode || codeOverride.isNotEmpty) {
      return null;
    }
    return 'Missing SMS login test code parameter. Pass '
        '--dart-define=$codeDefine=<code>.';
  }

  String get maskedPhone {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  void assertPhonePresent() {
    if (phone.isEmpty) {
      throw TestFailure(
        missingReason() ?? 'Missing SMS login test phone parameter.',
      );
    }
  }

  void assertPhoneAndCodePresent() {
    if (phone.isEmpty || !hasCode) {
      throw TestFailure(
        missingReason(requireCode: true) ??
            'Missing SMS login test phone/code parameters.',
      );
    }
  }
}
