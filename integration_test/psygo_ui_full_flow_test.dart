import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';
import 'package:psygo/main.dart' as app;
import 'package:psygo/backend/auth_state.dart';
import 'package:psygo/pages/chat/chat.dart';
import 'package:psygo/pages/chat_list/chat_list_body.dart';
import 'package:psygo/pages/login_signup/phone_login_page.dart';
import 'package:psygo/pages/main_screen/main_screen.dart';
import 'package:psygo/pages/team/employees_tab.dart';
import 'package:psygo/widgets/custom_hire_dialog.dart';
import 'package:psygo/widgets/employee_card.dart';
import 'package:psygo/widgets/employee_detail_sheet.dart';
import 'package:psygo/widgets/layouts/desktop_layout.dart';
import 'package:psygo/widgets/matrix.dart' as matrix_widget;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sms_test_credentials.dart';

class _CaseResult {
  final String id;
  final String name;
  final String status;
  final Duration duration;
  final String? detail;

  const _CaseResult({
    required this.id,
    required this.name,
    required this.status,
    required this.duration,
    this.detail,
  });
}

class _CaseRunner {
  final WidgetTester tester;
  final List<_CaseResult> _results = <_CaseResult>[];

  _CaseRunner(this.tester);

  List<_CaseResult> get results => List<_CaseResult>.unmodifiable(_results);

  int get passCount => _results.where((r) => r.status == 'PASS').length;
  int get failCount => _results.where((r) => r.status == 'FAIL').length;
  int get skipCount => _results.where((r) => r.status == 'SKIP').length;

  void log(String message) {
    debugPrint('[PSYGO_UI] $message');
  }

  void step(String message) {
    log('[STEP] $message');
  }

  void assertPass(String message) {
    log('[ASSERT_PASS] $message');
  }

  Future<void> runCase(
    String id,
    String name,
    Future<void> Function() body,
  ) async {
    final start = DateTime.now();
    log('[CASE_START] $id $name');
    try {
      await body();
      final duration = DateTime.now().difference(start);
      _results.add(
        _CaseResult(
          id: id,
          name: name,
          status: 'PASS',
          duration: duration,
        ),
      );
      log('[CASE_END] $id PASS duration=${duration.inMilliseconds}ms');
    } catch (e) {
      final duration = DateTime.now().difference(start);
      _results.add(
        _CaseResult(
          id: id,
          name: name,
          status: 'FAIL',
          duration: duration,
          detail: '$e',
        ),
      );
      log('[ASSERT_FAIL] $id $e');
      log('[CASE_END] $id FAIL duration=${duration.inMilliseconds}ms');
    }
  }

  void skipCase(String id, String name, String reason) {
    _results.add(
      _CaseResult(
        id: id,
        name: name,
        status: 'SKIP',
        duration: Duration.zero,
        detail: reason,
      ),
    );
    log('[CASE_END] $id SKIP reason=$reason');
  }

  void printSummary() {
    log('[SUMMARY] total=${_results.length} pass=$passCount fail=$failCount skip=$skipCount');
    for (final r in _results.where((e) => e.status == 'FAIL')) {
      log('[FAILED] ${r.id} reason=${r.detail}');
    }
    for (final r in _results.where((e) => e.status == 'SKIP')) {
      log('[SKIPPED] ${r.id} reason=${r.detail}');
    }
  }
}

const _zhTeam = '团队';
const _enTeam = 'Team';
const _zhRecruit = '招聘';
const _enRecruit = 'Custom Hire';
const _zhCreate = '创建';
const _enCreate = 'Create';
const _zhCancel = '取消';
const _enCancel = 'Cancel';
const _zhConfirm = '确认';
const _enConfirm = 'Confirm';
const _zhDeleteEmployee = '辞退员工';
const _enDeleteEmployee = 'Dismiss employee';
const _zhStartChat = '开始聊天';
const _enStartChat = 'Start chat';
const _zhPhoneHint = '请输入手机号';
const _enPhoneHint = 'Enter phone number';
const _zhCodeHint = '请输入验证码';
const _enCodeHint = 'Enter verification code';
const _zhGetCode = '获取验证码';
const _enGetCode = 'Get verification code';
const _zhLoginOrRegister = '登录 / 注册';
const _enLoginOrRegister = 'Login / Register';
const _zhEmployeeDeleted = '员工已辞退';
const _enEmployeeDeleted = 'Employee dismissed';
const _zhGuideDesc = '点击下方按钮开始招聘。提示：最多可招聘3个员工，招满后将无法继续招聘。';
const _enGuideDesc =
    'Tap the button below to start hiring. Tip: You can hire up to 3 employees. Recruiting is unavailable after reaching the limit.';
const _zhGuideAvatar = '先选一个头像';
const _enGuideAvatar = 'Pick an avatar';
const _zhGuideName = '再取一个名字';
const _enGuideName = 'Give them a name';
const _zhGuideCreate = '最后创建并等待入职';
const _enGuideCreate = 'Create and wait for onboarding';
const _zhNext = '下一步';
const _enNext = 'Next';
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

Finder? _firstExistingText(List<String> values) {
  for (final value in values) {
    final finder = _text(value);
    if (_exists(finder)) return finder;
  }
  return null;
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

Finder? _firstExistingControlByIcon(List<IconData> icons) {
  for (final icon in icons) {
    for (final element in find.byIcon(icon).evaluate()) {
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

Future<void> _tapFirstControlByIconOrThrow(
  WidgetTester tester,
  List<IconData> icons,
) async {
  final finder = _firstExistingControlByIcon(icons);
  if (finder == null) {
    throw TestFailure('Could not find any tappable control by icon: $icons');
  }
  await _tapControlOrThrow(
    tester,
    finder,
    description: 'icon control $icons',
  );
}

Future<void> _tapFirstDescendantControlOrThrow(
  WidgetTester tester,
  Finder scope, {
  required String description,
}) async {
  final tapTarget = find.descendant(
    of: scope,
    matching: find.byWidgetPredicate(_isEnabledTapTargetWidget),
  );
  if (!_exists(tapTarget)) {
    throw TestFailure(
      'Could not find any tappable descendant for: $description',
    );
  }
  await _tapControlOrThrow(
    tester,
    tapTarget.first,
    description: description,
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
    throw TestFailure(
      'Timed out waiting for home with expected account after sms login. '
      'expectedPhone=$phone currentMatrixUserId='
      '${_currentMatrixUserId(tester) ?? '<none>'}.',
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

Future<void> _loginWithSms(
  WidgetTester tester, {
  required PsygoSmsTestCredentials credentials,
  required _CaseRunner runner,
}) async {
  credentials.assertPhonePresent();
  await _waitForLoginOrHome(tester);
  await _logoutMismatchedAccountIfNeeded(tester, phone: credentials.phone);
  if (_isHomeVisible()) {
    await _ensureCurrentAccountMatchesPhoneOrThrow(
      tester,
      phone: credentials.phone,
      phase: 'existing session before SMS login',
    );
    runner.assertPass(
      'already logged in as ${_currentMatrixUserId(tester) ?? '<none>'}',
    );
    return;
  }

  if (!_isPhoneLoginVisible()) {
    await _navigateToPhoneLoginIfNeeded(tester);
    await _waitForLoginOrHome(tester);
  }

  await _logoutMismatchedAccountIfNeeded(tester, phone: credentials.phone);
  if (_isHomeVisible()) {
    await _ensureCurrentAccountMatchesPhoneOrThrow(
      tester,
      phone: credentials.phone,
      phase: 'route redirect before SMS login',
    );
    runner.assertPass(
      'home visible after route redirect as '
      '${_currentMatrixUserId(tester) ?? '<none>'}',
    );
    return;
  }

  runner.step('accept EULA checkbox');
  await _acceptPhoneLoginAgreementIfNeeded(tester);

  final phoneInput =
      _textFieldByHint([_zhPhoneHint, _enPhoneHint]).hitTestable();
  await _pumpUntil(
    tester,
    description: 'phone input field by hint',
    condition: () => _exists(phoneInput),
  );
  runner.step('fill phone number');
  await _setTextInFieldOrThrow(
    tester,
    phoneInput,
    value: credentials.phone,
    description: 'phone input',
  );

  final codeInput = _textFieldByHint([_zhCodeHint, _enCodeHint]).hitTestable();
  if (!_exists(codeInput)) {
    runner.step('request verification code');
    await _tapFirstControlByTextOrThrow(tester, [_zhGetCode, _enGetCode]);
    await _pumpUntil(
      tester,
      description: 'verification code input field by hint',
      timeout: const Duration(seconds: 45),
      condition: () => _exists(codeInput),
    );
  }

  if (credentials.hasCode) {
    runner.step('fill verification code');
    await _setTextInFieldOrThrow(
      tester,
      codeInput,
      value: credentials.code!,
      description: 'verification code input',
    );
  } else {
    runner.step('wait for manual verification code input in visible UI');
    await _pumpUntil(
      tester,
      description: 'manual verification code input or home',
      timeout: const Duration(minutes: 3),
      condition: () =>
          _isHomeVisible() ||
          (_exists(codeInput) &&
              tester
                      .widget<TextField>(codeInput.first)
                      .controller
                      ?.text
                      .trim()
                      .length !=
                  null &&
              (tester
                          .widget<TextField>(codeInput.first)
                          .controller
                          ?.text
                          .trim()
                          .length ??
                      0) >=
                  _verificationCodeLength),
    );
    if (_isHomeVisible()) {
      await _ensureCurrentAccountMatchesPhoneOrThrow(
        tester,
        phone: credentials.phone,
        phase: 'manual verification code wait',
      );
      runner.assertPass(
        'login success as ${_currentMatrixUserId(tester) ?? '<none>'}',
      );
      return;
    }
  }

  runner.step('submit login');
  await _tapFirstControlByTextOrThrow(
    tester,
    [_zhLoginOrRegister, _enLoginOrRegister],
  );

  await _pumpUntil(
    tester,
    description: 'home after login',
    timeout: const Duration(seconds: 90),
    condition: _isHomeVisible,
  );
  await _waitForExpectedAccountHomeAfterLoginOrThrow(
    tester,
    phone: credentials.phone,
  );
  runner.assertPass(
    'login success as ${_currentMatrixUserId(tester) ?? '<none>'}',
  );
}

Future<void> _goToTeamPage(WidgetTester tester, _CaseRunner runner) async {
  if (_exists(find.byType(EmployeesTab))) return;

  for (var i = 0; i < 3; i++) {
    final teamTextControl = _firstExistingControlByText([_zhTeam, _enTeam]);
    if (teamTextControl != null) {
      await _tapControlOrThrow(
        tester,
        teamTextControl,
        description: 'team navigation text control',
      );
    } else {
      final teamIconControl = _firstExistingControlByIcon([
        Icons.groups_outlined,
        Icons.groups_rounded,
      ]);
      if (teamIconControl == null) {
        break;
      }
      await _tapControlOrThrow(
        tester,
        teamIconControl,
        description: 'team navigation icon control',
      );
    }
    if (_exists(find.byType(EmployeesTab))) return;
  }

  await _pumpUntil(
    tester,
    description: 'team page',
    timeout: const Duration(seconds: 20),
    condition: () => _exists(find.byType(EmployeesTab)),
  );
  runner.assertPass('team page ready');
}

Future<int> _waitAndCountEmployeeCards(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    description: 'employee cards or empty team state',
    timeout: const Duration(seconds: 30),
    condition: () =>
        _exists(find.byType(EmployeeCard)) ||
        _exists(_text('雇佣第一位员工')) ||
        _exists(_text('Hire first employee')),
  );
  return find.byType(EmployeeCard).evaluate().length;
}

bool _isRecruitGuideVisibleOnTeam() {
  return _exists(_text(_zhGuideDesc)) || _exists(_text(_enGuideDesc));
}

bool _isRecruitDialogOpen() {
  return _exists(find.byType(CustomHireDialog)) ||
      _exists(_text(_zhCreate)) ||
      _exists(_text(_enCreate));
}

Future<void> _closeRecruitDialogIfOpen(WidgetTester tester) async {
  if (!_isRecruitDialogOpen()) return;
  final cancel = _firstExistingControlByText([_zhCancel, _enCancel]);
  if (cancel != null) {
    await _tapControlOrThrow(
      tester,
      cancel,
      description: 'close recruit dialog cancel button',
    );
    return;
  }
  await tester.pageBack();
  await _safePumpAndSettle(tester);
}

Future<bool> _openRecruitDialog(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final recruitTextControl =
      _firstExistingControlByText([_zhRecruit, _enRecruit]);
  if (recruitTextControl != null) {
    await _tapControlOrThrow(
      tester,
      recruitTextControl,
      description: 'open recruit dialog text control',
    );
  } else {
    final recruitIconControl = _firstExistingControlByIcon([Icons.add_rounded]);
    if (recruitIconControl == null) return false;
    await _tapControlOrThrow(
      tester,
      recruitIconControl,
      description: 'open recruit dialog icon control',
    );
  }

  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (_isRecruitDialogOpen()) return true;
    await tester.pump(const Duration(milliseconds: 250));
  }
  return false;
}

bool _isGuideOverlayVisibleInRecruitDialog() {
  return _exists(_text(_zhGuideAvatar)) ||
      _exists(_text(_enGuideAvatar)) ||
      _exists(_text(_zhGuideName)) ||
      _exists(_text(_enGuideName)) ||
      _exists(_text(_zhGuideCreate)) ||
      _exists(_text(_enGuideCreate)) ||
      _exists(_text(_zhNext)) ||
      _exists(_text(_enNext));
}

Future<String?> _completeRecruitGuideAndCreate(WidgetTester tester) async {
  const zhSuggestions = <String>['知夏', '明远', '安禾', '若溪'];
  const enSuggestions = <String>['Avery', 'Iris', 'Milo', 'Clara'];
  final allSuggestions = <String>[...zhSuggestions, ...enSuggestions];
  String? selectedName;

  for (var i = 0; i < 8; i++) {
    if (!_isGuideOverlayVisibleInRecruitDialog()) {
      break;
    }

    for (final name in allSuggestions) {
      final chip = _firstExistingControlByText([name]);
      if (chip != null) {
        await _tapControlOrThrow(
          tester,
          chip,
          description: 'guide name suggestion $name',
        );
        selectedName = name;
        break;
      }
    }

    final nextOrConfirm = _firstExistingControlByText([
      _zhNext,
      _enNext,
      _zhConfirm,
      _enConfirm,
    ]);
    if (nextOrConfirm != null) {
      await _tapControlOrThrow(
        tester,
        nextOrConfirm,
        description: 'recruit guide next or confirm button',
      );
    } else {
      break;
    }
  }

  await _pumpUntil(
    tester,
    description: 'recruit dialog closed after guide submit',
    timeout: const Duration(seconds: 45),
    condition: () => !_exists(find.byType(CustomHireDialog)),
  );
  return selectedName;
}

Future<void> _setEmployeeNameInRecruitDialog(
  WidgetTester tester,
  String name,
) async {
  final scopedInputs = find.descendant(
    of: find.byType(CustomHireDialog),
    matching: find.byType(TextField),
  );
  await _pumpUntil(
    tester,
    description: 'name field in recruit dialog',
    condition: () => _exists(scopedInputs),
  );
  await _setTextInFieldOrThrow(
    tester,
    scopedInputs,
    value: name,
    description: 'recruit dialog employee name',
  );
}

Future<String?> _createEmployeeFromRecruitDialog(
  WidgetTester tester, {
  required String preferredName,
}) async {
  if (_isGuideOverlayVisibleInRecruitDialog()) {
    return _completeRecruitGuideAndCreate(tester);
  }

  await _setEmployeeNameInRecruitDialog(tester, preferredName);
  await _tapFirstControlByTextOrThrow(tester, [_zhCreate, _enCreate]);

  await _pumpUntil(
    tester,
    description: 'recruit dialog closed after create',
    timeout: const Duration(seconds: 45),
    condition: () => !_exists(find.byType(CustomHireDialog)),
  );
  return preferredName;
}

List<EmployeeCard> _employeeCards(WidgetTester tester) {
  return tester.widgetList<EmployeeCard>(find.byType(EmployeeCard)).toList();
}

Set<String> _employeeAgentIds(WidgetTester tester) {
  return _employeeCards(tester)
      .map((card) => card.employee.agentId)
      .where((agentId) => agentId.trim().isNotEmpty)
      .toSet();
}

EmployeeCard? _employeeCardByAgentId(
  WidgetTester tester,
  String agentId,
) {
  for (final card in _employeeCards(tester)) {
    if (card.employee.agentId == agentId) return card;
  }
  return null;
}

int _employeeCardIndexByAgentId(WidgetTester tester, String agentId) {
  final cards = _employeeCards(tester);
  for (var i = 0; i < cards.length; i++) {
    if (cards[i].employee.agentId == agentId) return i;
  }
  return -1;
}

String? _pickDismissCandidateAgentId(
  WidgetTester tester, {
  Set<String> excludeAgentIds = const <String>{},
}) {
  String? fallbackAgentId;
  for (final card in _employeeCards(tester)) {
    final agentId = card.employee.agentId.trim();
    if (agentId.isEmpty || excludeAgentIds.contains(agentId)) continue;
    if (card.isOffboarding) continue;
    fallbackAgentId ??= agentId;
    if (card.employee.isReady) return agentId;
  }
  return fallbackAgentId;
}

Future<String> _waitForRecruitedAgentId(
  WidgetTester tester, {
  required Set<String> beforeIds,
  required String description,
  Duration timeout = const Duration(seconds: 60),
}) async {
  String? recruitedAgentId;
  await _pumpUntil(
    tester,
    description: description,
    timeout: timeout,
    condition: () {
      final newIds = _employeeAgentIds(tester).difference(beforeIds);
      if (newIds.isEmpty) return false;
      recruitedAgentId = newIds.first;
      return true;
    },
  );
  if (recruitedAgentId == null || recruitedAgentId!.isEmpty) {
    throw TestFailure('Could not resolve recruited agent id for: $description');
  }
  return recruitedAgentId!;
}

Future<EmployeeCard> _waitForRecruitedBotReady(
  WidgetTester tester, {
  required String agentId,
  Duration timeout = const Duration(seconds: 180),
}) async {
  EmployeeCard? target;
  await _pumpUntil(
    tester,
    description: 'recruited bot ready for chat',
    timeout: timeout,
    step: const Duration(seconds: 1),
    condition: () {
      final candidate = _employeeCardByAgentId(tester, agentId);
      if (candidate == null) return false;
      target = candidate;
      return candidate.employee.isReady &&
          (candidate.employee.matrixUserId?.isNotEmpty ?? false);
    },
  );
  if (target == null) {
    throw TestFailure('Recruited bot not found for agentId=$agentId');
  }
  return target!;
}

Future<void> _openEmployeeDetail(
  WidgetTester tester, {
  required String agentId,
}) async {
  final index = _employeeCardIndexByAgentId(tester, agentId);
  if (index < 0) {
    throw TestFailure('Employee card not found for agentId=$agentId');
  }

  final cardFinder = find.byType(EmployeeCard).at(index);
  await _tapFirstDescendantControlOrThrow(
    tester,
    cardFinder,
    description: 'employee card for agentId=$agentId',
  );

  await _pumpUntil(
    tester,
    description: 'employee detail sheet',
    timeout: const Duration(seconds: 15),
    condition: () => _exists(find.byType(EmployeeDetailSheet)),
  );
}

Future<void> _dismissEmployeeByAgentId(
  WidgetTester tester, {
  required String agentId,
  String? expectedToastLabel,
}) async {
  await _openEmployeeDetail(tester, agentId: agentId);
  await _tapFirstControlByTextOrThrow(
    tester,
    [_zhDeleteEmployee, _enDeleteEmployee],
  );
  await _tapFirstControlByTextOrThrow(tester, [_zhConfirm, _enConfirm]);

  await _pumpUntil(
    tester,
    description: 'employee removed from list',
    timeout: const Duration(seconds: 30),
    condition: () {
      final ids = _employeeCards(tester).map((e) => e.employee.agentId).toSet();
      return !ids.contains(agentId);
    },
  );

  if (expectedToastLabel != null) {
    final deletedToast =
        _firstExistingText([_zhEmployeeDeleted, _enEmployeeDeleted]);
    if (deletedToast == null) {
      throw TestFailure(
        'Expected dismiss toast after $expectedToastLabel, but it was not visible.',
      );
    }
  }
}

Future<int> _ensureRecruitSlotAvailable(
  WidgetTester tester,
  _CaseRunner runner, {
  Set<String> excludeAgentIds = const <String>{},
}) async {
  var count = await _waitAndCountEmployeeCards(tester);
  if (count < 3) {
    runner.step('botCount=$count, no dismiss needed');
    return count;
  }

  while (count >= 3) {
    final targetId = _pickDismissCandidateAgentId(
      tester,
      excludeAgentIds: excludeAgentIds,
    );
    if (targetId == null) {
      throw TestFailure(
        'botCount=$count but no dismiss candidate could be selected.',
      );
    }

    runner.step('botCount=$count, dismiss existing bot $targetId to free slot');
    await _dismissEmployeeByAgentId(
      tester,
      agentId: targetId,
      expectedToastLabel: 'free recruit slot',
    );
    count = await _waitAndCountEmployeeCards(tester);
  }

  runner.assertPass('recruit slot ready with botCount=$count');
  return count;
}

int _incomingMessageCount(ChatController chatController) {
  final timeline = chatController.timeline;
  if (timeline == null) return 0;
  final selfUserId = chatController.room.client.userID;
  return timeline.events
      .where(
        (event) =>
            event.type == EventTypes.Message && event.senderId != selfUserId,
      )
      .length;
}

String _shortRecruitName() {
  final suffix = (DateTime.now().millisecondsSinceEpoch % 100000000)
      .toString()
      .padLeft(8, '0');
  return 'UI$suffix';
}

Future<void> _runFullFlowTest(
  WidgetTester tester, {
  required PsygoSmsTestCredentials credentials,
}) async {
  SharedPreferences.setMockInitialValues({
    'chat.fluffy.show_no_google': false,
  });

  final runner = _CaseRunner(tester);
  var hasGuide = false;
  String? recruitedName;
  String? recruitedAgentId;
  String? chatVerifiedAgentId;

  app.main();
  await _safePumpAndSettle(tester);

  await runner.runCase('A_LOGIN_SMS', '自动登录（测试账号）', () async {
    await _loginWithSms(
      tester,
      credentials: credentials,
      runner: runner,
    );
  });

  await runner.runCase('B_GUIDE_BRANCH', '新手引导分支判定', () async {
    await _goToTeamPage(tester, runner);
    await _waitAndCountEmployeeCards(tester);
    hasGuide = _isRecruitGuideVisibleOnTeam();
    runner.assertPass('guideVisible=$hasGuide');
  });

  await runner.runCase('C_COMPLETE_GUIDE', '若有引导则完成引导', () async {
    if (!hasGuide) {
      runner.skipCase('C_COMPLETE_GUIDE', '若有引导则完成引导', 'no guide');
      return;
    }

    await _goToTeamPage(tester, runner);
    final beforeCount = await _waitAndCountEmployeeCards(tester);
    final beforeIds = _employeeAgentIds(tester);
    final opened = await _openRecruitDialog(tester);
    if (!opened) {
      throw TestFailure(
        'Guide branch expected recruit dialog, but it did not open.',
      );
    }

    final createdName = await _createEmployeeFromRecruitDialog(
      tester,
      preferredName: 'UI_AUTO_GUIDE',
    );
    recruitedName ??= createdName;

    await _pumpUntil(
      tester,
      description: 'employee card count increase after guide recruit',
      timeout: const Duration(seconds: 60),
      condition: () =>
          find.byType(EmployeeCard).evaluate().length >= beforeCount + 1,
    );
    recruitedAgentId = await _waitForRecruitedAgentId(
      tester,
      beforeIds: beforeIds,
      description: 'guide recruited agent id',
    );
    runner.assertPass('guide completed and recruited one employee');
  });

  await runner.runCase('D_BOT_COUNT_RULE', '无引导时校验 bot 数量规则', () async {
    if (hasGuide) {
      runner.skipCase(
        'D_BOT_COUNT_RULE',
        '无引导时校验 bot 数量规则',
        'guide flow was used',
      );
      return;
    }

    await _goToTeamPage(tester, runner);
    final count = await _waitAndCountEmployeeCards(tester);
    runner.step('current botCount=$count');
    final opened = await _openRecruitDialog(tester);

    if (count >= 3) {
      if (opened) {
        await _closeRecruitDialogIfOpen(tester);
        throw TestFailure(
          'Expected recruit blocked when botCount>=3, but dialog opened.',
        );
      }
      runner.assertPass('recruit blocked with botCount>=3');
      final countAfterDismiss =
          await _ensureRecruitSlotAvailable(tester, runner);
      if (countAfterDismiss >= 3) {
        throw TestFailure(
          'Expected botCount<3 after dismissing to free recruit slot, but got $countAfterDismiss.',
        );
      }
    } else {
      if (!opened) {
        throw TestFailure(
          'Expected recruit available when botCount<3, but dialog did not open.',
        );
      }
      runner.assertPass('recruit available with botCount<3');
      await _closeRecruitDialogIfOpen(tester);
    }
  });

  await runner.runCase('E_RECRUIT', '招聘流程', () async {
    await _goToTeamPage(tester, runner);
    final beforeCount = await _ensureRecruitSlotAvailable(tester, runner);
    final beforeIds = _employeeAgentIds(tester);

    final opened = await _openRecruitDialog(tester);
    if (!opened) {
      throw TestFailure('Recruit dialog did not open.');
    }

    final name = _shortRecruitName();
    final createdName = await _createEmployeeFromRecruitDialog(
      tester,
      preferredName: name,
    );
    recruitedName ??= createdName;

    final expectedName = createdName;
    await _pumpUntil(
      tester,
      description: 'new employee visible after recruit',
      timeout: const Duration(seconds: 60),
      condition: () {
        final countNow = find.byType(EmployeeCard).evaluate().length;
        final hasName =
            expectedName == null ? false : _exists(_text(expectedName));
        return countNow >= beforeCount + 1 || hasName;
      },
    );
    recruitedAgentId = await _waitForRecruitedAgentId(
      tester,
      beforeIds: beforeIds,
      description: 'recruit flow recruited agent id',
    );
    runner.assertPass('recruit success');
  });

  await runner.runCase('G_CHAT_RESPONSE', '和 bot 聊天并验证回应', () async {
    if (recruitedAgentId == null || recruitedAgentId!.isEmpty) {
      runner.skipCase('G_CHAT_RESPONSE', '和 bot 聊天并验证回应', 'no recruited bot');
      return;
    }

    await _goToTeamPage(tester, runner);
    final target = await _waitForRecruitedBotReady(
      tester,
      agentId: recruitedAgentId!,
    );

    await _openEmployeeDetail(tester, agentId: target.employee.agentId);
    await _tapFirstControlByTextOrThrow(
      tester,
      [_zhStartChat, _enStartChat],
    );

    await _pumpUntil(
      tester,
      description: 'chat room opened',
      timeout: const Duration(seconds: 20),
      condition: () => _exists(find.byType(ChatPageWithRoom)),
    );

    final chatController =
        tester.state<ChatController>(find.byType(ChatPageWithRoom).first);
    final incomingBefore = _incomingMessageCount(chatController);
    final message =
        '[UI_AUTO_CHAT_${DateTime.now().millisecondsSinceEpoch}] ping';

    await _pumpUntil(
      tester,
      description: 'chat input available',
      condition: () => _exists(find.byType(TextField)),
    );
    await _setTextInFieldOrThrow(
      tester,
      find.byType(TextField).last,
      value: message,
      description: 'chat composer',
    );

    if (_exists(find.byIcon(Icons.send_outlined))) {
      await _tapFirstControlByIconOrThrow(tester, [Icons.send_outlined]);
    } else {
      await tester.testTextInput.receiveAction(TextInputAction.done);
    }
    await _safePumpAndSettle(tester);

    await _pumpUntil(
      tester,
      description: 'sent message visible',
      timeout: const Duration(seconds: 20),
      condition: () => _exists(_text(message)),
    );

    await _pumpUntil(
      tester,
      description: 'bot response event received',
      timeout: const Duration(seconds: 60),
      step: const Duration(seconds: 1),
      condition: () {
        final latest =
            tester.state<ChatController>(find.byType(ChatPageWithRoom).first);
        return _incomingMessageCount(latest) > incomingBefore;
      },
    );
    chatVerifiedAgentId = target.employee.agentId;
    runner.assertPass('bot replied in timeline');
  });

  await runner.runCase('F_DISMISS', '辞退流程', () async {
    if (recruitedAgentId == null || recruitedAgentId!.isEmpty) {
      runner.skipCase('F_DISMISS', '辞退流程', 'no recruited bot');
      return;
    }
    if (chatVerifiedAgentId != recruitedAgentId) {
      runner.skipCase(
        'F_DISMISS',
        '辞退流程',
        'recruited bot chat not verified',
      );
      return;
    }

    await _goToTeamPage(tester, runner);
    final targetId = recruitedAgentId!;
    await _dismissEmployeeByAgentId(
      tester,
      agentId: targetId,
      expectedToastLabel: 'dismiss recruited bot',
    );
    runner.assertPass('dismiss toast shown');
  });

  runner.printSummary();
  expect(
    runner.failCount,
    0,
    reason: 'Some cases failed. Check [FAILED] lines in test output.',
  );
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final realSmsCredentials = PsygoSmsTestCredentials.maybeFromEnvironment();
  final hasRealSmsCredentials = realSmsCredentials != null;
  final realSmsSkipReason = PsygoSmsTestCredentials.missingReason();

  group('PsyGo UI Full Flow', () {
    testWidgets(
      'login + guide branch + recruit + chat + dismiss',
      (tester) async {
        final credentials = PsygoSmsTestCredentials.fromEnvironmentOrDefaults(
          defaultPhone: '12398764508',
          defaultCode: '000000',
        );
        await _runFullFlowTest(
          tester,
          credentials: credentials,
        );
      },
      skip: hasRealSmsCredentials,
    );

    if (realSmsSkipReason != null) {
      testWidgets(
        'real sms login + full flow',
        (tester) async {
          fail(realSmsSkipReason);
        },
        skip: true,
      );
      return;
    }

    testWidgets(
      'real sms login + full flow',
      (tester) async {
        debugPrint(
          '[PSYGO_UI] Real SMS full flow using phone ${realSmsCredentials!.maskedPhone}',
        );
        await _runFullFlowTest(
          tester,
          credentials: realSmsCredentials,
        );
      },
    );
  });
}
