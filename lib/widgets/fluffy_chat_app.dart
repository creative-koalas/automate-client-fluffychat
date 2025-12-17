import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Matrix;
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
import 'package:psygo/widgets/app_lock.dart';
import 'package:psygo/widgets/theme_builder.dart';
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
  static final GoRouter router = GoRouter(
    routes: AppRoutes.routes,
    debugLogDiagnostics: true,
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
  bool _isInitialStartup = true;  // Track if this is the first startup

  // Pending new user registration data
  String? _pendingToken;
  String? _pendingPhone;

  // Invitation code input
  final _invitationCodeController = TextEditingController();
  String? _invitationCodeError;
  bool _submittingInvitation = false;

  // Aliyun SDK secret key
  // 通过 --dart-define=ALIYUN_SECRET_KEY=your-secret-key 指定
  static const _secretKey = String.fromEnvironment('ALIYUN_SECRET_KEY',
      defaultValue: '');

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invitationCodeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // iOS FIX: Delay auth check to give system services time to initialize
    // On cold start, carrier/network services need time to become available
    // before Aliyun SDK can initialize properly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Wait 1 second after first frame to let iOS services initialize
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _checkAuthStateSafe();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 当应用从后台恢复时
    if (state == AppLifecycleState.resumed) {
      debugPrint('[AuthGate] App resumed from background, state=$_state, resumeRetryCount=$_resumeRetryCount');

      // iOS CRITICAL FIX: Always close Aliyun auth page when resuming from background
      // This prevents black screen caused by lingering auth page overlay
      OneClickLoginService.quitLoginPage();

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

    // iOS CRITICAL FIX: Handle retry after stale credentials detected
    if (_needsRetryAfterStaleCredentials) {
      debugPrint('[AuthGate] Retrying after stale credentials, directly triggering one-click login...');
      _needsRetryAfterStaleCredentials = false;

      // On mobile, directly trigger one-click login
      if (!kIsWeb && !_hasTriedAuth) {
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
        setState(() => _state = _AuthState.authenticated);
        return;
      }
      debugPrint('[AuthGate] Token refresh failed');
    }

    // 3. No valid token -> need to authenticate
    debugPrint('[AuthGate] No valid token, need authentication');

    // On web, redirect to login page (one-click login not supported)
    if (kIsWeb) {
      _redirectToLoginPage();
      return;
    }

    // On mobile, directly trigger one-click login
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

      // Handle based on onboarding status
      if (authResponse.onboardingCompleted) {
        // Already completed onboarding, login to Matrix
        await _loginMatrixAndProceed();
        // 所有操作完成后关闭授权页
        await OneClickLoginService.quitLoginPage();
      } else {
        // Need to complete onboarding first
        // 关闭授权页后再跳转 onboarding
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
        debugPrint('[AuthGate] Login error but retries available ($resumeRetryCount/$_maxResumeRetries), staying in checking state');
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

      // Get login client - this handles returning the main client if not logged in
      var client = await matrix.getLoginClient();

      debugPrint('[AuthGate] Client database: ${client.database}');
      debugPrint('[AuthGate] Client name: ${client.clientName}');
      debugPrint('[AuthGate] Client isLogged: ${client.isLogged()}');
      debugPrint('[AuthGate] Client deviceID: ${client.deviceID}');

      // Note: Encryption is disabled for this Matrix server
      if (!client.isLogged()) {
        debugPrint('[AuthGate] Client not logged in, performing Matrix login...');

        // Clear old data before login
        await client.clear();
        debugPrint('[AuthGate] Client data cleared');

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

        setState(() => _state = _AuthState.authenticated);

        // Navigate to main page after successful login
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final router = GoRouter.of(context);
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

      // Client is already logged in, just proceed
      debugPrint('[AuthGate] Client already logged in with deviceID=${client.deviceID}');
      setState(() => _state = _AuthState.authenticated);

      // Navigate to main page if not already there
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final router = GoRouter.of(context);
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

      // iOS FIX: Auto-retry with fresh credentials on first failure
      // On cold start after deleting data, the credentials from backend might be stale
      // Clear all credentials and trigger a fresh one-click login flow
      if (!_hasRetriedMatrixLogin) {
        debugPrint('[AuthGate] Matrix login failed, clearing credentials and retrying with fresh login...');
        _hasRetriedMatrixLogin = true;  // Mark that we've retried once

        final auth = context.read<PsygoAuthState>();
        await auth.markLoggedOut();

        if (!mounted) return;

        setState(() {
          _state = _AuthState.checking;
          _hasTriedAuth = false;
        });

        // Trigger fresh one-click login (will call _loginMatrixAndProceed again with new credentials)
        await _checkAuthState();
        return;
      }

      // iOS FIX: Handle Matrix login failures after retry
      // Common causes: Network issues, stale credentials, encryption problems
      // Don't force logout - user's automate token is still valid!
      if (e.toString().contains('Upload key failed') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('SocketException')) {
        debugPrint('[AuthGate] Matrix encryption/network error - possible causes:');
        debugPrint('[AuthGate] 1. Network issue (cannot reach Matrix homeserver)');
        debugPrint('[AuthGate] 2. Stale encryption keys or database corruption');
        debugPrint('[AuthGate] 3. Matrix server not running or not accessible');

        setState(() {
          _state = _AuthState.error;
          _errorMessage = 'Matrix 服务器连接失败\n\n可能原因：\n- Matrix 服务器未启动或无法访问\n- 网络连接问题\n- 数据库损坏\n\n请确保：\n1. Matrix 服务器正在运行\n2. 网络连接正常\n3. 或重新登录获取新凭证';
        });
        return;
      }

      setState(() {
        _state = _AuthState.error;
        _errorMessage = 'Matrix 服务连接失败: ${e.toString()}\n\n请重试或重新登录';
      });
    }
  }


  void _redirectToLoginPage() {
    // Mobile: Stay in AuthGate, don't redirect to /login-signup
    // AuthGate will handle one-click login automatically
    if (!kIsWeb) {
      setState(() => _state = _AuthState.error);
      return;
    }

    // Web only: redirect to /login-signup for manual login options
    setState(() => _state = _AuthState.needsLogin);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navKey = PsygoApp.router.routerDelegate.navigatorKey;
      final ctx = navKey.currentContext;
      if (ctx == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _redirectToLoginPage());
        return;
      }

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

  /// Navigate to onboarding page for new users.
  /// Sets authenticated state and navigates to onboarding.
  void _navigateToOnboardingThenAuthenticate() {
    setState(() => _state = _AuthState.authenticated);
    _navigateToOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<PsygoAuthState>();

    // If logged out externally, reset state
    if (!auth.isLoggedIn && _state == _AuthState.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _state = _AuthState.checking;
          _hasTriedAuth = false;
          _hasRetriedMatrixLogin = false;
        });
        _checkAuthState();
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
        return widget.child ?? const SizedBox.shrink();
    }
  }

  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              width: 100,
              height: 100,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    final isMatrixError = _errorMessage?.contains('Matrix') ?? false;
    final isNetworkError = _errorMessage?.contains('网络') ?? false;

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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/logo.png',
                  width: 100,
                  height: 100,
                ),
                const SizedBox(height: 32),
                const Text(
                  '新用户注册',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '手机号：$_pendingPhone',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 32),
                const Text('请输入邀请码完成注册'),
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
