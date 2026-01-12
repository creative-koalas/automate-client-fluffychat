import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:psygo/backend/backend.dart';
import 'package:psygo/services/one_click_login.dart';
import 'package:psygo/core/config.dart';
import 'package:psygo/config/routes.dart';
import 'package:psygo/config/setting_keys.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/permission_service.dart';
import 'package:psygo/utils/window_service.dart';
import 'package:psygo/widgets/app_lock.dart';
import 'package:psygo/widgets/theme_builder.dart';
import 'package:psygo/utils/app_update_service.dart';
import 'package:psygo/utils/agreement_check_service.dart';
import 'package:psygo/utils/client_manager.dart';
import '../utils/custom_scroll_behaviour.dart';
import 'matrix.dart';

class PsygoApp extends StatelessWidget {
  final Widget? testWidget;
  final List<Client> clients;
  final String? pincode;
  final SharedPreferences store;

  const PsygoApp({
    super.key,
    this.testWidget,
    required this.clients,
    required this.store,
    this.pincode,
  });

  /// getInitialLink may rereturn the value multiple times if this view is
  /// opened multiple times for example if the user logs out after they logged
  /// in with qr code or magic link.
  static bool gotInitialLink = false;

  // Router must be outside of build method so that hot reload does not reset
  // the current path.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    routes: AppRoutes.routes,
    debugLogDiagnostics: true,
    navigatorKey: navigatorKey,
  );

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      builder: (context, themeMode, primaryColor) => MaterialApp.router(
        title: AppSettings.applicationName.value,
        themeMode: themeMode,
        theme: FluffyThemes.buildTheme(context, Brightness.light, primaryColor),
        darkTheme:
            FluffyThemes.buildTheme(context, Brightness.dark, primaryColor),
        scrollBehavior: CustomScrollBehavior(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
        builder: (context, child) => ChangeNotifierProvider(
          create: (_) => PsygoAuthState()..load(),
          child: Builder(
            builder: (context) {
              final auth = context.read<PsygoAuthState>();
              return Provider<PsygoApiClient>(
                create: (_) => PsygoApiClient(auth),
                child: AppLockWidget(
                  pincode: pincode,
                  clients: clients,
                  child: Matrix(
                    clients: clients,
                    store: store,
                    child: _AutomateAuthGate(
                      clients: clients,
                      store: store,
                      child: testWidget ?? child,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Professional AuthGate with token refresh and direct one-click login
///
/// Flow:
/// 1. App launch -> check stored token
/// 2. Token valid -> proceed to main app
/// 3. Token expired + refresh token -> try refresh
/// 4. No valid token -> directly show Aliyun auth popup (no intermediate page)
/// 5. After login success -> login Matrix -> proceed to main app
class _AutomateAuthGate extends StatefulWidget {
  final Widget? child;
  final List<Client> clients;
  final SharedPreferences store;

  const _AutomateAuthGate({
    this.child,
    required this.clients,
    required this.store,
  });

  @override
  State<_AutomateAuthGate> createState() => _AutomateAuthGateState();
}

enum _AuthState {
  checking,      // Checking stored token
  refreshing,    // Refreshing expired token
  authenticating, // Performing one-click login
  authenticated, // Successfully authenticated
  needsLogin,    // Needs login, show login page
  waitingInvitationCode, // Waiting for invitation code input (new user)
  error,         // Error occurred
}

class _AutomateAuthGateState extends State<_AutomateAuthGate>
    with WidgetsBindingObserver {
  _AuthState _state = _AuthState.checking;
  String? _errorMessage;
  bool _hasTriedAuth = false;
  bool _needsRetryAfterStaleCredentials = false;
  bool _hasRetriedMatrixLogin = false;  // Track if we already retried Matrix login
  int _resumeRetryCount = 0;  // Track resume retry attempts to avoid infinite loops
  static const int _maxResumeRetries = 3;  // Max retries on resume
  bool _blockedByForceUpdate = false;  // Track if blocked by force update

  // Pending new user registration data
  String? _pendingToken;
  String? _pendingPhone;

  // Invitation code input
  final _invitationCodeController = TextEditingController();
  String? _invitationCodeError;
  bool _submittingInvitation = false;

  // 保存 auth 引用，避免在 dispose 中访问 context
  PsygoAuthState? _authState;

  // Aliyun SDK secret key
  // 通过 --dart-define=ALIYUN_SECRET_KEY=your-secret-key 指定
  static const _secretKey = String.fromEnvironment(
    'ALIYUN_SECRET_KEY',
    defaultValue: '',
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invitationCodeController.dispose();
    // 移除认证状态监听（使用保存的引用，避免访问 context）
    _authState?.removeListener(_onAuthStateChanged);
    _authState = null;
    // 停止后台检查服务
    AppUpdateService.stopBackgroundCheck();
    AgreementCheckService.stopBackgroundCheck();
    super.dispose();
  }

  /// 认证状态变化回调
  void _onAuthStateChanged() {
    if (!mounted) return;

    final auth = context.read<PsygoAuthState>();
    debugPrint('[AuthGate] Auth state changed: isLoggedIn=${auth.isLoggedIn}, onboardingCompleted=${auth.onboardingCompleted}');

    // 登出时重置状态
    if (!auth.isLoggedIn && _state == _AuthState.authenticated) {
      debugPrint('[AuthGate] User logged out, resetting state');
      setState(() {
        _state = _AuthState.needsLogin;
        _hasTriedAuth = false;
        _hasRetriedMatrixLogin = false;
        _resumeRetryCount = 0;
      });
      return;
    }

    // 登录成功时更新状态
    if (auth.isLoggedIn && auth.onboardingCompleted && _state != _AuthState.authenticated) {
      // 检查 Matrix 是否也已登录
      try {
        final matrix = Matrix.of(context);
        if (matrix.client.isLogged()) {
          debugPrint('[AuthGate] User logged in with Matrix, updating state to authenticated');
          setState(() => _state = _AuthState.authenticated);
          _startAgreementCheckService();
        }
      } catch (e) {
        debugPrint('[AuthGate] Could not check Matrix state: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 监听认证状态变化（保存引用以便在 dispose 中使用）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _authState = context.read<PsygoAuthState>();
      _authState?.addListener(_onAuthStateChanged);
    });

    // iOS FIX: Delay auth check to give system services time to initialize
    // On cold start, carrier/network services need time to become available
    // before Aliyun SDK can initialize properly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Wait 1 second after first frame to let iOS services initialize
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _checkAuthStateSafe();
        }
      });
    });
  }

  /// 应用启动时初始化更新检查
  Future<void> _initUpdateCheck() async {
    try {
      final api = context.read<PsygoApiClient>();

      // 获取可用的 context（优先使用 Navigator context，否则使用当前 widget context）
      BuildContext? getNavigatorContext() {
        return PsygoApp.navigatorKey.currentContext;
      }

      // 获取最佳可用 context
      // Navigator context 可能在登录完成后才可用，所以先用当前 context
      BuildContext getAvailableContext() {
        return getNavigatorContext() ?? context;
      }

      // 启动后台检查服务
      AppUpdateService.startBackgroundCheck(api, getAvailableContext);

      // 不再等待 Navigator，直接使用当前 context 执行检查
      // 当前 context 在 MaterialApp.builder 内，可以正常显示 Dialog
      if (!mounted) return;

      // 立即执行一次检查
      final updateService = AppUpdateService(api);
      final canContinue = await updateService.checkAndPrompt(context);

      // 处理强制更新阻止
      if (!canContinue && mounted) {
        setState(() {
          _blockedByForceUpdate = true;
        });
      }
    } catch (e) {
      debugPrint('[AppUpdate] Init update check failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 当应用从后台恢复时
    if (state == AppLifecycleState.resumed) {
      debugPrint('[AuthGate] App resumed from background, state=$_state, resumeRetryCount=$_resumeRetryCount');

      // iOS CRITICAL FIX: Always close Aliyun auth page when resuming from background
      // This prevents black screen caused by lingering auth page overlay
      if (PlatformInfos.isMobile) {
        OneClickLoginService.quitLoginPage();
      }

      // 应用恢复时检查更新（先检查 App 更新，再检查协议）
      AppUpdateService.onAppResumed();
      // 协议检查（仅已登录用户）
      if (_state == _AuthState.authenticated) {
        AgreementCheckService.onAppResumed();
      }

      // iOS FIX: Handle permission approval during auth check
      // When user slowly approves network permissions, SDK initialization may timeout
      // Auto-retry when app resumes after permission approval (with retry limit)
      if ((_state == _AuthState.checking || _state == _AuthState.error) &&
          _resumeRetryCount < _maxResumeRetries) {
        debugPrint('[AuthGate] In $_state state, retrying auth check after resume (attempt ${_resumeRetryCount + 1}/$_maxResumeRetries)');
        _resumeRetryCount++;

        setState(() {
          _hasTriedAuth = false;
          _hasRetriedMatrixLogin = false;
          _state = _AuthState.checking;  // Keep in checking state, don't flash error UI
        });

        // Wait a bit for network to be fully ready
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _checkAuthStateSafe();
        });
      } else if (_resumeRetryCount >= _maxResumeRetries && _state == _AuthState.error) {
        debugPrint('[AuthGate] Max resume retries reached, showing persistent error');
        // Stay in error state to show the error message
      }
    }
  }

  Future<void> _checkAuthStateSafe() async {
    try {
      await _checkAuthState();
    } catch (e, s) {
      debugPrint('[AuthGate] Unhandled error in auth check: $e');
      debugPrint('$s');
      if (!mounted) return;

      // If we still have retry attempts, stay in checking state (don't show error)
      // User will see loading screen instead of error flash
      if (_resumeRetryCount < _maxResumeRetries) {
        debugPrint('[AuthGate] Error occurred but retries available, staying in checking state');
        // Keep state as checking, will be retried on next resume
        return;
      }

      // No more retries, show error
      setState(() {
        _state = _AuthState.error;
        _errorMessage = '登录状态检查失败，请重试';
      });
    }
  }

  Future<void> _checkAuthState() async {
    final auth = context.read<PsygoAuthState>();
    final api = context.read<PsygoApiClient>();

    // Ensure auth state is loaded from storage before checking
    // This is critical because PsygoAuthState()..load() in Provider.create
    // does not wait for load() to complete (cascade operator returns immediately)
    await auth.load();

    debugPrint('[AuthGate] Checking auth state...');

    // 在检查登录状态之前先检查更新（只在首次检查时执行）
    if (!_hasTriedAuth) {
      await _initUpdateCheck();
      if (_blockedByForceUpdate) return;  // 被强制更新阻止，不继续
    }

    // iOS CRITICAL FIX: Handle retry after stale credentials detected
    if (_needsRetryAfterStaleCredentials) {
      debugPrint('[AuthGate] Retrying after stale credentials, directly triggering one-click login...');
      _needsRetryAfterStaleCredentials = false;

      // On mobile only, directly trigger one-click login
      if (PlatformInfos.isMobile && !_hasTriedAuth) {
        _hasTriedAuth = true;
        await _performDirectLogin();
      } else {
        _redirectToLoginPage();
      }
      return;
    }

    // 1. Check if already logged in with valid token
    if (auth.isLoggedIn && auth.hasValidToken) {
      debugPrint('[AuthGate] Automate token is valid');

      // Check if Matrix is already logged in
      final matrix = Matrix.of(context);
      final isMatrixLoggedIn = matrix.widget.clients.any((c) => c.isLogged());

      if (isMatrixLoggedIn) {
        // Both automate and Matrix are logged in, proceed to app
        debugPrint('[AuthGate] Matrix also logged in, proceeding to app');
        // PC端：切换到主窗口模式
        if (PlatformInfos.isDesktop) {
          await WindowService.switchToMainWindow();
        }
        setState(() => _state = _AuthState.authenticated);
        return;
      }

      // Automate logged in but Matrix not logged in
      if (!auth.onboardingCompleted) {
        // Need to complete onboarding first
        debugPrint('[AuthGate] Onboarding not completed, navigating to onboarding');
        _navigateToOnboardingThenAuthenticate();
        return;
      }

      // Onboarding completed but Matrix not logged in - login Matrix
      debugPrint('[AuthGate] Onboarding completed, logging into Matrix');
      await _loginMatrixAndProceed();
      return;
    }

    // 2. Token expired but have refresh token -> try to refresh
    if (auth.isLoggedIn && auth.refreshToken != null) {
      debugPrint('[AuthGate] Token expired, attempting refresh...');
      setState(() => _state = _AuthState.refreshing);

      final success = await api.refreshAccessToken();
      if (success) {
        debugPrint('[AuthGate] Token refreshed successfully');
        // PC端：切换到主窗口模式
        if (PlatformInfos.isDesktop) {
          await WindowService.switchToMainWindow();
        }
        setState(() => _state = _AuthState.authenticated);
        return;
      }
      debugPrint('[AuthGate] Token refresh failed');
    }

    // 3. No valid token -> need to authenticate
    debugPrint('[AuthGate] No valid token, need authentication');

    // On web or desktop, redirect to login page (one-click login SDK not supported)
    // One-click login SDK only works on mobile (Android/iOS)
    if (kIsWeb || PlatformInfos.isDesktop) {
      _redirectToLoginPage();
      return;
    }

    // On mobile only, directly trigger one-click login
    if (!_hasTriedAuth) {
      _hasTriedAuth = true;
      await _performDirectLogin();
    } else {
      // Already tried once, show login page for manual retry
      _redirectToLoginPage();
    }
  }

  Future<void> _performDirectLogin() async {
    // 不设置 authenticating 状态，避免显示"正在登录"
    // SDK 授权页会直接弹出覆盖当前界面
    _errorMessage = null;

    try {
      debugPrint('[AuthGate] Starting one-click login...');

      // Perform the complete one-click login flow
      final loginToken = await OneClickLoginService.performOneClickLogin(
        secretKey: _secretKey,
        timeout: 10000,
      );

      debugPrint('[AuthGate] Got token from Aliyun, calling backend...');

      // Step 1: Verify phone number
      final api = context.read<PsygoApiClient>();
      final verifyResponse = await api.verifyPhone(loginToken);
      debugPrint('[AuthGate] ===== Backend verifyPhone Response =====');
      debugPrint('[AuthGate] Phone: ${verifyResponse.phone}');
      debugPrint('[AuthGate] isNewUser: ${verifyResponse.isNewUser}');
      debugPrint('[AuthGate] pendingToken: ${verifyResponse.pendingToken}');
      debugPrint('[AuthGate] =========================================');

      if (!mounted) return;

      // Step 2: New user needs invitation code
      if (verifyResponse.isNewUser) {
        debugPrint('[AuthGate] Backend says isNewUser=true, showing invitation code screen');

        // CRITICAL: Change state BEFORE closing auth page to prevent auto-retry
        // When we close the auth page, iOS will trigger AppLifecycleState.resumed
        // If state is still _AuthState.checking, auto-retry will trigger
        _pendingToken = verifyResponse.pendingToken;
        _pendingPhone = verifyResponse.phone;

        setState(() => _state = _AuthState.waitingInvitationCode);

        // Now safe to close Aliyun auth page
        await OneClickLoginService.quitLoginPage();

        debugPrint('[AuthGate] New user detected, showing invitation code screen');
        return;
      }

      if (!mounted) return;

      // Step 3: Complete login (old user, no invitation code needed)
      debugPrint('[AuthGate] Backend says isNewUser=false, proceeding with login (no invitation code needed)');
      final authResponse = await api.completeLogin(
        verifyResponse.pendingToken,
      );

      debugPrint('[AuthGate] Backend completeLogin success, onboardingCompleted=${authResponse.onboardingCompleted}');

      if (!mounted) return;

      // Handle based on onboarding status
      if (authResponse.onboardingCompleted) {
        // Already completed onboarding, login to Matrix
        // CRITICAL iOS FIX: Change state BEFORE closing auth page to prevent auto-retry
        // When we close auth page, iOS triggers AppLifecycleState.resumed
        // If state is still _checking, didChangeAppLifecycleState will trigger auto-retry
        setState(() => _state = _AuthState.authenticating);

        await OneClickLoginService.quitLoginPage();
        await _loginMatrixAndProceed();
      } else {
        // Need to complete onboarding first
        // CRITICAL iOS FIX: Change state BEFORE closing auth page
        setState(() => _state = _AuthState.authenticating);

        await OneClickLoginService.quitLoginPage();
        // Important: Navigate BEFORE setting authenticated state to avoid
        // GoRouter's redirect to /login-signup (which checks Matrix client)
        _navigateToOnboardingThenAuthenticate();
      }
    } on SwitchLoginMethodException {
      // User clicked "其他方式登录" button, redirect to login page
      debugPrint('[AuthGate] User chose to switch login method');
      // SDK 已自动关闭授权页，无需手动关闭
      _redirectToLoginPage();
      return;
    } catch (e) {
      debugPrint('[AuthGate] One-click login error: $e');
      // 出错时关闭授权页
      await OneClickLoginService.quitLoginPage();

      // Check if user cancelled
      final errorStr = e.toString();
      if (errorStr.contains('USER_CANCEL') || errorStr.contains('用户取消')) {
        // User cancelled, redirect to login page for other options
        _redirectToLoginPage();
        return;
      }

      // If we still have retry attempts, stay in checking state (don't show error)
      // Will be automatically retried when app resumes
      if (_resumeRetryCount < _maxResumeRetries) {
        debugPrint('[AuthGate] Login error but retries available ($_resumeRetryCount/$_maxResumeRetries), staying in checking state');
        // Keep state as checking, will be retried
        return;
      }

      // No more retries, show error
      setState(() {
        _state = _AuthState.error;
        _errorMessage = _parseErrorMessage(errorStr);
      });
    }
  }

  String _parseErrorMessage(String error) {
    // 网络权限被拒绝的常见错误
    if (error.contains('网络不可用') ||
        error.contains('Network is unreachable') ||
        error.contains('网络连接失败') ||
        error.contains('Connection failed')) {
      return '网络连接失败\n\n请检查：\n1. 是否允许了"无线局域网与蜂窝网络"权限\n2. 网络连接是否正常\n\n如需修改权限，请点击下方"打开设置"按钮';
    }
    if (error.contains('预取号失败')) {
      return '网络环境不支持一键登录\n\n可能原因：\n- 未连接到运营商网络\n- 网络权限被拒绝\n\n请检查网络设置或使用其他登录方式';
    }
    if (error.contains('SDK初始化失败')) {
      return '初始化失败\n\n请检查：\n- 网络连接是否正常\n- 是否允许了网络权限\n\n如需修改权限，请点击"打开设置"';
    }
    return error.replaceAll('Exception: ', '');
  }

  Future<void> _loginMatrixAndProceed() async {
    final auth = context.read<PsygoAuthState>();
    final matrixAccessToken = auth.matrixAccessToken;
    final matrixUserId = auth.matrixUserId;
    final matrixDeviceId = auth.matrixDeviceId;

    if (matrixAccessToken == null || matrixUserId == null) {
      debugPrint('[AuthGate] Missing Matrix credentials for Matrix login');
      setState(() {
        _state = _AuthState.error;
        _errorMessage = 'Matrix 凭证缺失，请重新登录';
      });
      return;
    }

    debugPrint('[AuthGate] Matrix credentials: userId=$matrixUserId, deviceId=$matrixDeviceId');

    try {
      final matrix = Matrix.of(context);

      // 使用用户专属的 client（基于 Matrix 用户 ID 命名数据库）
      // 这样每个用户都有独立的数据库，切换账号时不会有脏数据
      final client = await ClientManager.getOrCreateClientForUser(
        matrixUserId,
        widget.store,
      );

      debugPrint('[AuthGate] Client database: ${client.database}');
      debugPrint('[AuthGate] Client name: ${client.clientName}');
      debugPrint('[AuthGate] Client isLogged: ${client.isLogged()}');
      debugPrint('[AuthGate] Client deviceID: ${client.deviceID}');

      // 确保 client 在 clients 列表中
      if (!widget.clients.contains(client)) {
        widget.clients.add(client);
        debugPrint('[AuthGate] Client added to clients list, length=${widget.clients.length}');
      }

      // Note: Encryption is disabled for this Matrix server
      // 检查是否需要重新登录：未登录 或 userID 不匹配（切换账号的情况）
      final needsLogin = !client.isLogged() || client.userID != matrixUserId;
      if (needsLogin) {
        // 如果已登录但 userID 不匹配，先退出旧账号
        if (client.isLogged() && client.userID != matrixUserId) {
          try {
            await client.logout();
          } catch (_) {}
        }

        // Clear old data before login (仅清除内存状态，数据库保留)
        await client.clear();

        // Set homeserver before login
        final homeserverUrl = Uri.parse(PsygoConfig.matrixHomeserver);
        debugPrint('[AuthGate] Setting homeserver: $homeserverUrl');
        await client.checkHomeserver(homeserverUrl);

        debugPrint('[AuthGate] Attempting Matrix login: matrixUserId=$matrixUserId');

        // Use access_token directly
        await client.init(
          newToken: matrixAccessToken,
          newUserID: matrixUserId,
          newHomeserver: homeserverUrl,
          newDeviceName: PlatformInfos.clientName,
        );
        debugPrint('[AuthGate] Matrix login success, deviceID=${client.deviceID}');

        // CRITICAL: Ensure client is in the clients list after successful login
        // client.init(newToken:...) may not trigger onLoginStateChanged event,
        // so we need to explicitly add the client to the list here
        if (!widget.clients.contains(client)) {
          widget.clients.add(client);
          debugPrint('[AuthGate] Client added to clients list, length=${widget.clients.length}');
        } else {
          debugPrint('[AuthGate] Client already in clients list, length=${widget.clients.length}');
        }

        // 设置当前 client 为活跃客户端
        matrix.setActiveClient(client);
        debugPrint('[AuthGate] Set active client to ${client.clientName}');

        // PC端：切换到主窗口模式
        if (PlatformInfos.isDesktop) {
          await WindowService.switchToMainWindow();
        }

        setState(() => _state = _AuthState.authenticated);

        // 启动协议检查后台服务
        _startAgreementCheckService();

        // Navigate to main page after successful login
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final router = PsygoApp.router;
            if (router.routerDelegate.currentConfiguration.fullPath != '/rooms') {
              router.go('/rooms');
            }
          }
        });

        if (PlatformInfos.isMobile) {
          Future.delayed(const Duration(seconds: 1), () {
            PermissionService.instance.requestPushPermissions();
          });
        }
        return;
      }

      // Client is already logged in with correct userID, just proceed
      debugPrint('[AuthGate] Client already logged in with correct userID=${client.userID}, deviceID=${client.deviceID}');

      // Ensure client is in the clients list
      if (!widget.clients.contains(client)) {
        widget.clients.add(client);
        debugPrint('[AuthGate] Client added to clients list (already logged in), length=${widget.clients.length}');
      }

      // 设置当前 client 为活跃客户端
      matrix.setActiveClient(client);
      debugPrint('[AuthGate] Set active client to ${client.clientName}');

      // PC端：切换到主窗口模式
      if (PlatformInfos.isDesktop) {
        await WindowService.switchToMainWindow();
      }

      setState(() => _state = _AuthState.authenticated);

      // 启动协议检查后台服务
      _startAgreementCheckService();

      // Navigate to main page if not already there
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final router = PsygoApp.router;
          if (router.routerDelegate.currentConfiguration.fullPath != '/rooms') {
            router.go('/rooms');
          }
        }
      });

      if (PlatformInfos.isMobile) {
        Future.delayed(const Duration(seconds: 1), () {
          PermissionService.instance.requestPushPermissions();
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[AuthGate] Matrix login failed: $e');
      debugPrint('[AuthGate] Stack trace: $stackTrace');

      final errorStr = e.toString();
      final isInvalidToken = errorStr.contains('M_UNKNOWN_TOKEN') ||
          errorStr.contains('Invalid access token');

      // Token 失效：清除所有状态并跳转到登录页
      if (isInvalidToken) {
        debugPrint('[AuthGate] Matrix token invalid, clearing all auth state and redirecting to login...');
        await _clearAllAuthStateAndRedirectToLogin();
        return;
      }

      // 网络/加密错误：显示错误信息
      if (errorStr.contains('Upload key failed') ||
          errorStr.contains('Connection refused') ||
          errorStr.contains('SocketException')) {
        debugPrint('[AuthGate] Matrix encryption/network error');

        setState(() {
          _state = _AuthState.error;
          _errorMessage = '无法连接到聊天服务\n\n请检查网络连接后重试';
        });
        return;
      }

      // 其他错误：尝试重试一次
      if (!_hasRetriedMatrixLogin) {
        debugPrint('[AuthGate] Matrix login failed, retrying once...');
        _hasRetriedMatrixLogin = true;

        final auth = context.read<PsygoAuthState>();
        await auth.markLoggedOut();

        if (!mounted) return;

        setState(() {
          _state = _AuthState.checking;
          _hasTriedAuth = false;
        });

        await _checkAuthState();
        return;
      }

      // 重试后仍然失败：清除状态并跳转登录
      debugPrint('[AuthGate] Matrix login failed after retry, clearing auth and redirecting to login...');
      await _clearAllAuthStateAndRedirectToLogin();
    }
  }


  // 路由重定向重试计数，防止无限递归
  int _redirectRetryCount = 0;
  static const int _maxRedirectRetries = 5;

  void _redirectToLoginPage() {
    // Mobile only: Stay in AuthGate, don't redirect to /login-signup
    // AuthGate will handle one-click login automatically
    if (PlatformInfos.isMobile) {
      setState(() => _state = _AuthState.error);
      return;
    }

    // Web and Desktop: redirect to /login-signup for manual login options
    setState(() => _state = _AuthState.needsLogin);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final navKey = PsygoApp.router.routerDelegate.navigatorKey;
      final ctx = navKey.currentContext;
      if (ctx == null) {
        // 防止无限递归：限制重试次数
        _redirectRetryCount++;
        if (_redirectRetryCount >= _maxRedirectRetries) {
          debugPrint('[AuthGate] Max redirect retries reached, giving up');
          _redirectRetryCount = 0;
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _redirectToLoginPage());
        return;
      }

      // 重置重试计数
      _redirectRetryCount = 0;

      final router = GoRouter.of(ctx);
      if (router.routerDelegate.currentConfiguration.fullPath != '/login-signup') {
        router.go('/login-signup');
      }
    });
  }

  /// Retry one-click login after canceling invitation code input
  void _retryOneClickLogin() {
    debugPrint('[AuthGate] User canceled invitation code, retrying one-click login');

    // Clear invitation code state
    _pendingToken = null;
    _pendingPhone = null;
    _invitationCodeController.clear();
    _invitationCodeError = null;

    // Reset auth attempt flags to allow one-click login again
    _hasTriedAuth = false;
    _hasRetriedMatrixLogin = false;

    // Go back to checking state and retry
    setState(() {
      _state = _AuthState.checking;
    });

    _checkAuthStateSafe();
  }

  void _navigateToOnboarding() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navKey = PsygoApp.router.routerDelegate.navigatorKey;
      final ctx = navKey.currentContext;
      if (ctx == null) return;

      GoRouter.of(ctx).go('/onboarding-chatbot');
    });
  }

  /// 启动协议检查后台服务
  Future<void> _startAgreementCheckService() async {
    final api = context.read<PsygoApiClient>();

    BuildContext? getNavigatorContext() {
      return PsygoApp.navigatorKey.currentContext;
    }

    AgreementCheckService.startBackgroundCheck(
      api,
      () => getNavigatorContext() ?? context,
      _forceLogout,
    );

    // 等待 Navigator 可用
    var waitAttempts = 0;
    const maxWaitAttempts = 10;
    BuildContext? navContext;
    while (waitAttempts < maxWaitAttempts) {
      navContext = getNavigatorContext();
      if (navContext != null) break;
      await Future.delayed(const Duration(milliseconds: 300));
      waitAttempts++;
      if (!mounted) return;
    }

    if (navContext == null) return;

    // 立即执行一次检查
    final agreementService = AgreementCheckService(api);
    await agreementService.checkAndHandle(navContext);
  }

  /// 强制登出（协议未接受时调用）
  Future<void> _forceLogout() async {
    debugPrint('[AuthGate] Force logout triggered - agreement not accepted');

    // 停止后台检查服务
    AgreementCheckService.stopBackgroundCheck();

    // 清除 Automate 认证状态
    final auth = context.read<PsygoAuthState>();
    await auth.markLoggedOut();

    // 退出所有 Matrix 客户端
    // 注意：client.logout() 会触发 onLoginStateChanged，自动执行：
    // - 清除图片缓存 (MxcImage.clearCache)
    // - 清除用户缓存 (DesktopLayout.clearUserCache)
    // - 从 store 移除 clientName
    final matrix = Matrix.of(context);
    final clients = List.from(matrix.widget.clients);
    for (final client in clients) {
      try {
        if (client.isLogged()) {
          await client.logout();
          debugPrint('[AuthGate] Matrix client logged out');
        }
      } catch (e) {
        debugPrint('[AuthGate] Matrix client logout error: $e');
      }
    }

    if (!mounted) return;

    // PC端：切换回登录小窗口
    if (PlatformInfos.isDesktop) {
      await WindowService.switchToLoginWindow();
    }

    // 重置 AuthGate 状态
    setState(() {
      _state = _AuthState.needsLogin;
      _hasTriedAuth = false;  // 允许一键登录重新触发
      _hasRetriedMatrixLogin = false;
      _resumeRetryCount = 0;
    });

    // 路由跳转由 Matrix.onLoginStateChanged 自动处理
    // 移动端：跳转到 / 后触发一键登录
    if (PlatformInfos.isMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkAuthStateSafe();
      });
    }
  }

  /// 清除所有认证状态并跳转到登录页（Token 失效时调用）
  Future<void> _clearAllAuthStateAndRedirectToLogin() async {
    debugPrint('[AuthGate] Clearing all auth state and redirecting to login...');

    // 停止后台检查服务
    AgreementCheckService.stopBackgroundCheck();

    // 清除 Automate 认证状态
    final auth = context.read<PsygoAuthState>();
    await auth.markLoggedOut();

    // 退出所有 Matrix 客户端
    // 注意：client.logout() 会触发 onLoginStateChanged，自动执行：
    // - 清除图片缓存 (MxcImage.clearCache)
    // - 清除用户缓存 (DesktopLayout.clearUserCache)
    // - 从 store 移除 clientName
    try {
      final matrix = Matrix.of(context);
      final clients = List.from(matrix.widget.clients);
      for (final client in clients) {
        if (client.isLogged()) {
          try {
            await client.logout();
            debugPrint('[AuthGate] Matrix client logged out');
          } catch (e) {
            debugPrint('[AuthGate] Matrix logout error: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[AuthGate] Could not access Matrix: $e');
    }

    if (!mounted) return;

    // 重置 AuthGate 状态（允许自动一键登录重试）
    setState(() {
      _state = _AuthState.needsLogin;
      _hasTriedAuth = false;
      _hasRetriedMatrixLogin = false;
      _resumeRetryCount = 0;
    });

    // PC端：切换到登录小窗口
    if (PlatformInfos.isDesktop) {
      await WindowService.switchToLoginWindow();
    }

    // 跳转到登录页
    PsygoApp.router.go('/login-signup');

    debugPrint('[AuthGate] Auth state cleared, redirected to login page');
  }

  /// Navigate to onboarding page for new users.
  /// Sets authenticated state and navigates to onboarding.
  void _navigateToOnboardingThenAuthenticate() async {
    // PC端：切换到主窗口模式
    if (PlatformInfos.isDesktop) {
      await WindowService.switchToMainWindow();
    }
    setState(() => _state = _AuthState.authenticated);
    _navigateToOnboarding();
  }


  @override
  Widget build(BuildContext context) {
    final auth = context.watch<PsygoAuthState>();

    // If logged out externally (e.g., 401 error), clear all auth state including Matrix
    if (!auth.isLoggedIn && _state == _AuthState.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 清除所有认证状态（包括 Matrix）并跳转到登录页
        // 这确保了 401 错误时 Matrix 也会被正确登出
        _clearAllAuthStateAndRedirectToLogin();
      });
    }

    switch (_state) {
      case _AuthState.checking:
        // 显示加载界面，避免黑屏
        return _buildLoadingScreen('正在检查登录状态...');

      case _AuthState.refreshing:
        return _buildLoadingScreen('正在验证登录状态...');

      case _AuthState.authenticating:
        return _buildLoadingScreen('正在登录...');

      case _AuthState.waitingInvitationCode:
        return _buildInvitationCodeScreen();

      case _AuthState.error:
        return _buildErrorScreen();

      case _AuthState.needsLogin:
      case _AuthState.authenticated:
        // 被强制更新阻止时显示提示
        if (_blockedByForceUpdate) {
          return _buildForceUpdateBlockedScreen();
        }
        return widget.child ?? const SizedBox.shrink();
    }
  }

  /// 强制更新阻止界面
  Widget _buildForceUpdateBlockedScreen() {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.system_update_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                '需要更新',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '当前版本过低，请更新后继续使用',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () async {
                  // 重新触发更新检查
                  setState(() {
                    _blockedByForceUpdate = false;
                  });
                  await _initUpdateCheck();
                },
                child: const Text('重新检查'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(String message) {
    // PC端使用新的主题风格
    if (PlatformInfos.isDesktop) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;

      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF0A1628),
                      const Color(0xFF0D2233),
                      const Color(0xFF0F3D3E),
                    ]
                  : [
                      const Color(0xFFF0F4F8),
                      const Color(0xFFE8EFF5),
                      const Color(0xFFE0F2F1),
                    ],
            ),
          ),
          child: Center(
            child: Image.asset(
              isDark ? 'assets/logo_dark.png' : 'assets/logo_transparent.png',
              width: 100,
              height: 100,
            ),
          ),
        ),
      );
    }

    // 非PC端：只显示 logo，根据主题深浅色切换
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Image.asset(
          isDark ? 'assets/logo_dark.png' : 'assets/logo.png',
          width: 100,
          height: 100,
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    final isMatrixError = _errorMessage?.contains('Matrix') ?? false;
    final isNetworkError = _errorMessage?.contains('网络') ?? false;

    // PC端使用新的主题风格
    if (PlatformInfos.isDesktop) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final textColor = isDark ? Colors.white : const Color(0xFF1A2332);
      final subtitleColor = isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF666666);
      final accentColor = isDark ? const Color(0xFF00FF9F) : const Color(0xFF00A878);
      const errorColor = Color(0xFFFF6B6B);

      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF0A1628),
                      const Color(0xFF0D2233),
                      const Color(0xFF0F3D3E),
                    ]
                  : [
                      const Color(0xFFF0F4F8),
                      const Color(0xFFE8EFF5),
                      const Color(0xFFE0F2F1),
                    ],
            ),
          ),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Error icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: errorColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: errorColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Title
                  Text(
                    '登录失败',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Error message
                  Text(
                    _errorMessage ?? '未知错误',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: subtitleColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Buttons
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      // Retry button
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: isDark
                                ? [
                                    const Color(0xFF00B386),
                                    const Color(0xFF00D4A1),
                                  ]
                                : [
                                    accentColor.withValues(alpha: 0.9),
                                    accentColor,
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _state = _AuthState.checking;
                                _hasTriedAuth = false;
                                _hasRetriedMatrixLogin = false;
                                _resumeRetryCount = 0;
                              });
                              _checkAuthStateSafe();
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              child: const Text(
                                '重试',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (isMatrixError)
                        TextButton(
                          onPressed: () async {
                            final auth = context.read<PsygoAuthState>();
                            await auth.markLoggedOut();
                            setState(() {
                              _state = _AuthState.checking;
                              _hasTriedAuth = false;
                              _hasRetriedMatrixLogin = false;
                              _resumeRetryCount = 0;
                            });
                            _checkAuthStateSafe();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          ),
                          child: const Text('重新登录'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 非PC端保持原样
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                '登录失败',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? '未知错误',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _state = _AuthState.checking;
                        _hasTriedAuth = false;
                        _hasRetriedMatrixLogin = false;
                        _resumeRetryCount = 0;  // Reset retry counter
                      });
                      _checkAuthStateSafe();
                    },
                    child: const Text('重试'),
                  ),
                  if (isNetworkError) ...[
                    FilledButton.icon(
                      onPressed: () async {
                        await PermissionService.instance.openSettings();
                      },
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('打开设置'),
                    ),
                  ],
                  if (isMatrixError) ...[
                    FilledButton(
                      onPressed: () async {
                        // Clear all credentials and force re-login
                        final auth = context.read<PsygoAuthState>();
                        await auth.markLoggedOut();

                        setState(() {
                          _state = _AuthState.checking;
                          _hasTriedAuth = false;
                          _hasRetriedMatrixLogin = false;
                          _resumeRetryCount = 0;  // Reset retry counter
                        });
                        _checkAuthStateSafe();
                      },
                      child: const Text('重新登录'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvitationCodeScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                isDark ? 'assets/logo_dark.png' : 'assets/logo.png',
                width: 100,
                height: 100,
              ),
              const SizedBox(height: 32),
              Text(
                '新用户注册',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '手机号：$_pendingPhone',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '请输入邀请码完成注册',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _invitationCodeController,
                decoration: InputDecoration(
                  labelText: '邀请码',
                  hintText: '请输入邀请码',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  errorText: _invitationCodeError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                textCapitalization: TextCapitalization.characters,
                enabled: !_submittingInvitation,
                onChanged: (_) {
                  if (_invitationCodeError != null) {
                    setState(() => _invitationCodeError = null);
                  }
                },
                onSubmitted: (_) => _submitInvitationCode(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submittingInvitation ? null : _retryOneClickLogin,
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submittingInvitation ? null : _submitInvitationCode,
                      child: _submittingInvitation
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('确认'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitInvitationCode() async {
    final code = _invitationCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _invitationCodeError = '请输入邀请码');
      return;
    }

    setState(() {
      _submittingInvitation = true;
      _invitationCodeError = null;
    });

    try {
      debugPrint('[AuthGate] Completing registration with invitation code');
      final api = context.read<PsygoApiClient>();
      final authResponse = await api.completeLogin(
        _pendingToken!,
        invitationCode: code,
      );

      debugPrint('[AuthGate] Registration success, onboardingCompleted=${authResponse.onboardingCompleted}');

      if (!mounted) return;

      // CRITICAL: Reload auth state to ensure isLoggedIn is updated
      // This prevents build() from thinking we're logged out and triggering re-auth
      final auth = context.read<PsygoAuthState>();
      await auth.load();
      debugPrint('[AuthGate] Auth state reloaded after registration');

      if (!mounted) return;

      // Handle based on onboarding status
      if (authResponse.onboardingCompleted) {
        // Already completed onboarding, login to Matrix
        await _loginMatrixAndProceed();
      } else {
        // Need to complete onboarding first
        _navigateToOnboardingThenAuthenticate();
      }
    } catch (e) {
      debugPrint('[AuthGate] Registration error: $e');
      if (!mounted) return;
      setState(() {
        _submittingInvitation = false;
        _invitationCodeError = e.toString();
      });
    }
  }
}
