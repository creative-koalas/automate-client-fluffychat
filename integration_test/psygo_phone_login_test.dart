import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:psygo/main.dart' as app;
import 'package:psygo/backend/auth_state.dart';
import 'package:psygo/pages/chat_list/chat_list_body.dart';
import 'package:psygo/pages/login_signup/phone_login_page.dart';
import 'package:psygo/pages/main_screen/main_screen.dart';
import 'package:psygo/pages/team/employees_tab.dart';
import 'package:psygo/widgets/layouts/desktop_layout.dart';
import 'package:psygo/widgets/matrix.dart' as matrix_widget;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sms_test_credentials.dart';

const _zhPhoneHint = '请输入手机号';
const _enPhoneHint = 'Enter phone number';
const _zhCodeHint = '请输入验证码';
const _enCodeHint = 'Enter verification code';
const _zhGetCode = '获取验证码';
const _enGetCode = 'Get verification code';
const _zhLoginOrRegister = '登录 / 注册';
const _enLoginOrRegister = 'Login / Register';
const _verificationCodeLength = 6;

Finder _text(String value) => find.text(value, findRichText: true);

bool _exists(Finder finder) => finder.evaluate().isNotEmpty;

Finder _textFieldByHint(List<String> hints) {
  return find.byWidgetPredicate((widget) {
    if (widget is! TextField) return false;
    final hint = widget.decoration?.hintText;
    return hint != null && hints.contains(hint);
  });
}

Finder _editableTextIn(Finder scope) {
  return find.descendant(of: scope, matching: find.byType(EditableText));
}

bool _isEnabledTapTargetWidget(Widget widget) {
  if (widget is ButtonStyleButton) return widget.enabled;
  if (widget is IconButton) return widget.onPressed != null;
  if (widget is InkWell) return widget.onTap != null;
  if (widget is ChoiceChip) return widget.onSelected != null;
  if (widget is ActionChip) return widget.onPressed != null;
  if (widget is FilterChip) return widget.onSelected != null;
  if (widget is InputChip) {
    return widget.onPressed != null ||
        widget.onSelected != null ||
        widget.onDeleted != null;
  }
  if (widget is ListTile) return widget.onTap != null;
  if (widget is Checkbox) return widget.onChanged != null;
  if (widget is Switch) return widget.onChanged != null;
  return false;
}

Finder _finderForElement(Element element) {
  return find.byElementPredicate((candidate) => identical(candidate, element));
}

Element? _nearestTapTargetElement(Element element) {
  if (_isEnabledTapTargetWidget(element.widget)) return element;

  Element? tapTarget;
  element.visitAncestorElements((ancestor) {
    if (_isEnabledTapTargetWidget(ancestor.widget)) {
      tapTarget = ancestor;
      return false;
    }
    return true;
  });
  return tapTarget;
}

Finder? _firstExistingControlByText(List<String> values) {
  for (final value in values) {
    for (final element in _text(value).evaluate()) {
      final tapTarget = _nearestTapTargetElement(element);
      if (tapTarget == null) continue;

      final finder = _finderForElement(tapTarget);
      final hitTestable = finder.hitTestable();
      if (_exists(hitTestable)) return hitTestable;
      if (_exists(finder)) return finder;
    }
  }
  return null;
}

Future<void> _safePumpAndSettle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpUntil(
  WidgetTester tester, {
  required bool Function() condition,
  required String description,
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) return;
    await tester.pump(step);
  }
  throw TestFailure('Timed out waiting for: $description');
}

Future<void> _tapControlOrThrow(
  WidgetTester tester,
  Finder finder, {
  required String description,
}) async {
  if (!_exists(finder)) {
    throw TestFailure('Could not find control to tap: $description');
  }
  final hitTestable = finder.hitTestable();
  final target = _exists(hitTestable) ? hitTestable.first : finder.first;
  await tester.ensureVisible(target);
  await tester.tapAt(tester.getCenter(target, warnIfMissed: false));
  await _safePumpAndSettle(tester);
}

Future<void> _tapFirstControlByTextOrThrow(
  WidgetTester tester,
  List<String> values,
) async {
  final finder = _firstExistingControlByText(values);
  if (finder == null) {
    throw TestFailure('Could not find any tappable control by text: $values');
  }
  await _tapControlOrThrow(
    tester,
    finder,
    description: 'text control $values',
  );
}

Future<void> _setTextInFieldOrThrow(
  WidgetTester tester,
  Finder field, {
  required String value,
  required String description,
}) async {
  if (!_exists(field)) {
    throw TestFailure('Could not find field to enter text: $description');
  }

  await tester.ensureVisible(field.first);

  final editable = _editableTextIn(field);
  final inputTarget = _exists(editable) ? editable.first : field.first;
  await tester.showKeyboard(inputTarget);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(inputTarget, value);

  await _safePumpAndSettle(tester);
}

bool _isHomeVisible() {
  return _exists(find.byType(EmployeesTab)) ||
      _exists(find.byType(ChatListViewBody)) ||
      _exists(find.byType(MainScreen)) ||
      _exists(find.byType(DesktopLayout));
}

bool _isPhoneLoginVisible() {
  return _exists(find.byType(PhoneLoginPage)) ||
      _exists(_text(_zhPhoneHint)) ||
      _exists(_text(_enPhoneHint));
}

String? _normalizedOrNull(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized;
}

String? _matrixLocalpart(String? matrixUserId) {
  final normalized = _normalizedOrNull(matrixUserId);
  if (normalized == null) return null;
  final withoutAt =
      normalized.startsWith('@') ? normalized.substring(1) : normalized;
  final colonIndex = withoutAt.indexOf(':');
  final localpart =
      colonIndex >= 0 ? withoutAt.substring(0, colonIndex) : withoutAt;
  return localpart.toLowerCase();
}

Set<String> _expectedMatrixLocalpartsForPhone(String phone) {
  final normalizedPhone = phone.trim().toLowerCase();
  return <String>{
    normalizedPhone,
    'at$normalizedPhone',
  };
}

BuildContext _appContextOrThrow(WidgetTester tester) {
  final candidates = <Finder>[
    find.byType(PhoneLoginPage),
    find.byType(MainScreen),
    find.byType(DesktopLayout),
    find.byType(Scaffold),
  ];
  for (final candidate in candidates) {
    if (_exists(candidate)) {
      return tester.element(candidate.first);
    }
  }
  throw TestFailure('Could not locate app BuildContext');
}

String? _currentMatrixUserId(WidgetTester tester) {
  try {
    final context = _appContextOrThrow(tester);
    final authMatrixUserId =
        _normalizedOrNull(context.read<PsygoAuthState>().matrixUserId);
    if (authMatrixUserId != null) return authMatrixUserId;

    final matrix = matrix_widget.Matrix.of(context);
    final activeUserId = _normalizedOrNull(matrix.clientOrNull?.userID);
    if (activeUserId != null) return activeUserId;

    for (final client in matrix.widget.clients) {
      final userId = _normalizedOrNull(client.userID);
      if (client.isLogged() && userId != null) {
        return userId;
      }
    }
  } catch (_) {}
  return null;
}

bool _currentAccountMatchesPhone(WidgetTester tester, String phone) {
  final localpart = _matrixLocalpart(_currentMatrixUserId(tester));
  if (localpart == null) return false;
  return _expectedMatrixLocalpartsForPhone(phone).contains(localpart);
}

Future<void> _ensureCurrentAccountMatchesPhoneOrThrow(
  WidgetTester tester, {
  required String phone,
  required String phase,
}) async {
  final currentMatrixUserId = _currentMatrixUserId(tester);
  if (_currentAccountMatchesPhone(tester, phone)) return;
  throw TestFailure(
    'Expected phone $phone to map to Matrix localpart '
    '${_expectedMatrixLocalpartsForPhone(phone).join(' or ')}, '
    'but current account is ${currentMatrixUserId ?? '<none>'} during $phase.',
  );
}

Future<void> _logoutMismatchedAccountIfNeeded(
  WidgetTester tester, {
  required String phone,
}) async {
  if (!_isHomeVisible()) return;
  final currentMatrixUserId = _currentMatrixUserId(tester);
  if (_currentAccountMatchesPhone(tester, phone)) {
    debugPrint(
      '[PSYGO_UI] Home already visible with expected account '
      '$currentMatrixUserId for phone $phone.',
    );
    return;
  }

  debugPrint(
    '[PSYGO_UI] Home visible with mismatched account '
    '$currentMatrixUserId for phone $phone, logging out first.',
  );

  final context = _appContextOrThrow(tester);
  await context.read<PsygoAuthState>().markLoggedOut();
  await _safePumpAndSettle(tester);
  await _navigateToPhoneLoginIfNeeded(tester);

  try {
    await _pumpUntil(
      tester,
      description: 'phone login after mismatched account logout',
      timeout: const Duration(seconds: 30),
      condition: () =>
          _isPhoneLoginVisible() ||
          (!_isHomeVisible() && _currentMatrixUserId(tester) == null),
    );
  } on TestFailure {
    throw TestFailure(
      'Failed to clear mismatched account before SMS login. '
      'expectedPhone=$phone, currentMatrixUserId='
      '${_currentMatrixUserId(tester) ?? currentMatrixUserId ?? '<none>'}.',
    );
  }
}

Future<void> _waitForLoginOrHome(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    description: 'phone login or home',
    timeout: const Duration(seconds: 45),
    condition: () => _isPhoneLoginVisible() || _isHomeVisible(),
  );
}

Future<void> _navigateToPhoneLoginIfNeeded(WidgetTester tester) async {
  if (_isPhoneLoginVisible() || _isHomeVisible()) return;
  final scaffoldFinder = find.byType(Scaffold);
  if (!_exists(scaffoldFinder)) return;
  final context = tester.element(scaffoldFinder.first);
  GoRouter.of(context).go('/login-signup');
  await _safePumpAndSettle(tester);
}

Future<void> _acceptPhoneLoginAgreementIfNeeded(WidgetTester tester) async {
  final checkboxFinder = find.byType(Checkbox).hitTestable();
  if (!_exists(checkboxFinder)) return;
  final checkbox = tester.widget<Checkbox>(checkboxFinder.first);
  if (checkbox.value == true) return;
  await tester.tap(checkboxFinder.first);
  await _safePumpAndSettle(tester);
}

List<String> _visibleErrorTexts(WidgetTester tester) {
  const keywords = <String>[
    '验证码',
    '登录',
    '失败',
    '错误',
    '手机号',
    '短信',
    'code',
    'login',
    'phone',
    'error',
    'failed',
  ];

  final values = <String>{};
  for (final textWidget in tester.widgetList<Text>(find.byType(Text))) {
    final value =
        (textWidget.data ?? textWidget.textSpan?.toPlainText() ?? '').trim();
    if (value.isEmpty || value.length > 120) continue;
    if (keywords.any(
      (keyword) => value.toLowerCase().contains(keyword.toLowerCase()),
    )) {
      values.add(value);
    }
  }
  return values.take(8).toList();
}

Future<void> _waitForCodeInputOrThrow(WidgetTester tester) async {
  final codeInput = _textFieldByHint([_zhCodeHint, _enCodeHint]).hitTestable();
  try {
    await _pumpUntil(
      tester,
      description: 'verification code input field by hint',
      timeout: const Duration(seconds: 45),
      condition: () => _exists(codeInput),
    );
  } on TestFailure {
    final details = _visibleErrorTexts(tester);
    final suffix =
        details.isEmpty ? '' : ' Visible texts: ${details.join(' | ')}';
    throw TestFailure(
      'Timed out waiting for verification code input field.$suffix',
    );
  }
}

Future<void> _waitForHomeAfterLoginOrThrow(WidgetTester tester) async {
  try {
    await _pumpUntil(
      tester,
      description: 'home after sms login',
      timeout: const Duration(seconds: 90),
      condition: _isHomeVisible,
    );
  } on TestFailure {
    final details = _visibleErrorTexts(tester);
    final suffix =
        details.isEmpty ? '' : ' Visible texts: ${details.join(' | ')}';
    throw TestFailure('Timed out waiting for home after sms login.$suffix');
  }
}

Future<void> _waitForExpectedAccountHomeAfterLoginOrThrow(
  WidgetTester tester, {
  required String phone,
}) async {
  try {
    await _pumpUntil(
      tester,
      description: 'home with expected account after sms login',
      timeout: const Duration(seconds: 90),
      condition: () =>
          _isHomeVisible() && _currentAccountMatchesPhone(tester, phone),
    );
  } on TestFailure {
    final details = _visibleErrorTexts(tester);
    final suffix =
        details.isEmpty ? '' : ' Visible texts: ${details.join(' | ')}';
    throw TestFailure(
      'Timed out waiting for home with expected account after sms login. '
      'expectedPhone=$phone currentMatrixUserId='
      '${_currentMatrixUserId(tester) ?? '<none>'}.$suffix',
    );
  }
}

String _fieldValue(WidgetTester tester, Finder field) {
  if (!_exists(field)) return '';
  final textField = tester.widget<TextField>(field.first);
  return textField.controller?.text.trim() ?? '';
}

Future<void> _requestSmsCode(
  WidgetTester tester, {
  required String phone,
}) async {
  await _waitForLoginOrHome(tester);
  await _logoutMismatchedAccountIfNeeded(tester, phone: phone);
  if (_isHomeVisible()) {
    await _ensureCurrentAccountMatchesPhoneOrThrow(
      tester,
      phone: phone,
      phase: 'existing session before SMS login',
    );
    return;
  }

  if (!_isPhoneLoginVisible()) {
    await _navigateToPhoneLoginIfNeeded(tester);
    await _waitForLoginOrHome(tester);
  }

  await _logoutMismatchedAccountIfNeeded(tester, phone: phone);
  if (_isHomeVisible()) {
    await _ensureCurrentAccountMatchesPhoneOrThrow(
      tester,
      phone: phone,
      phase: 'route redirect before SMS login',
    );
    return;
  }

  await _acceptPhoneLoginAgreementIfNeeded(tester);

  final phoneInput =
      _textFieldByHint([_zhPhoneHint, _enPhoneHint]).hitTestable();
  await _pumpUntil(
    tester,
    description: 'phone input field by hint',
    condition: () => _exists(phoneInput),
  );

  await _setTextInFieldOrThrow(
    tester,
    phoneInput,
    value: phone,
    description: 'phone input',
  );

  final codeInput = _textFieldByHint([_zhCodeHint, _enCodeHint]).hitTestable();
  if (!_exists(codeInput)) {
    await _tapFirstControlByTextOrThrow(tester, [_zhGetCode, _enGetCode]);
    await _waitForCodeInputOrThrow(tester);
  }
}

Future<void> _waitForManualCodeEntryOrHome(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final codeInput = _textFieldByHint([_zhCodeHint, _enCodeHint]).hitTestable();
  debugPrint(
    '[PSYGO_UI] Waiting for manual verification code entry in visible UI.',
  );
  await _pumpUntil(
    tester,
    description: 'manual verification code entry or home',
    timeout: timeout,
    condition: () =>
        _isHomeVisible() ||
        (_exists(codeInput) &&
            _fieldValue(tester, codeInput).length >= _verificationCodeLength),
  );
}

Future<void> _loginWithSms(
  WidgetTester tester, {
  required PsygoSmsTestCredentials credentials,
}) async {
  credentials.assertPhonePresent();
  await _requestSmsCode(tester, phone: credentials.phone);
  if (_isHomeVisible()) {
    await _ensureCurrentAccountMatchesPhoneOrThrow(
      tester,
      phone: credentials.phone,
      phase: 'SMS login reuse path',
    );
    return;
  }

  final codeInput = _textFieldByHint([_zhCodeHint, _enCodeHint]).hitTestable();
  if (credentials.hasCode) {
    await _setTextInFieldOrThrow(
      tester,
      codeInput,
      value: credentials.code!,
      description: 'verification code input',
    );
    await _tapFirstControlByTextOrThrow(
      tester,
      [_zhLoginOrRegister, _enLoginOrRegister],
    );
  } else {
    await _waitForManualCodeEntryOrHome(tester);
    if (!_isHomeVisible()) {
      await _tapFirstControlByTextOrThrow(
        tester,
        [_zhLoginOrRegister, _enLoginOrRegister],
      );
    }
  }

  await _waitForHomeAfterLoginOrThrow(tester);
  await _waitForExpectedAccountHomeAfterLoginOrThrow(
    tester,
    phone: credentials.phone,
  );
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final credentials = PsygoSmsTestCredentials.maybeFromEnvironment();
  final skipReason = PsygoSmsTestCredentials.missingReason();

  if (skipReason != null) {
    testWidgets(
      'real sms phone login',
      (tester) async {
        fail(skipReason);
      },
      skip: true,
    );
    return;
  }

  testWidgets(
    'real sms phone login',
    (tester) async {
      expect(credentials, isNotNull);
      debugPrint(
        '[PSYGO_UI] SMS login test using phone ${credentials!.maskedPhone}',
      );

      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      app.main();
      await _safePumpAndSettle(tester);

      await _loginWithSms(tester, credentials: credentials);
      expect(_isHomeVisible(), isTrue);
      expect(_currentAccountMatchesPhone(tester, credentials.phone), isTrue);
    },
  );
}
