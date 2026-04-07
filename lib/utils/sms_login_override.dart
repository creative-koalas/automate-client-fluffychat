/// Narrow production-only overrides for internal SMS login test accounts.
library;

abstract final class SmsLoginOverride {
  static const String prodTestPhone = '12398764509';
  static const String prodTestCode = '123456';

  static bool shouldSkipSmsSend({
    required String phone,
    required String namespace,
  }) {
    return _isProdNamespace(namespace) &&
        normalizePhone(phone) == prodTestPhone;
  }

  static bool shouldBypassPhoneValidation({
    required String phone,
    required String namespace,
  }) {
    return shouldSkipSmsSend(phone: phone, namespace: namespace);
  }

  static String resolveLoginCode({
    required String phone,
    required String inputCode,
    required String namespace,
  }) {
    if (shouldSkipSmsSend(phone: phone, namespace: namespace)) {
      return prodTestCode;
    }
    return inputCode.trim();
  }

  static String normalizePhone(String phone) => phone.trim();

  static bool _isProdNamespace(String namespace) {
    final normalized = namespace.trim().toLowerCase();
    return normalized == 'prod' || normalized == 'production';
  }
}
