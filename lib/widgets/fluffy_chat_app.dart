import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:automate/automate/backend/backend.dart';
import 'package:automate/automate/services/one_click_login.dart';
import 'package:automate/automate/core/config.dart';
import 'package:automate/config/routes.dart';
import 'package:automate/config/setting_keys.dart';
import 'package:automate/config/themes.dart';
import 'package:automate/l10n/l10n.dart';
import 'package:automate/utils/platform_infos.dart';
import 'package:automate/widgets/app_lock.dart';
import 'package:automate/widgets/theme_builder.dart';
import '../utils/custom_scroll_behaviour.dart';
import 'matrix.dart';

class AutomateApp extends StatelessWidget {
  final Widget? testWidget;
  final List<Client> clients;
  final String? pincode;
  final SharedPreferences store;

  const AutomateApp({
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
          create: (_) => AutomateAuthState()..load(),
          child: Builder(
            builder: (context) {
              final auth = context.read<AutomateAuthState>();
              return Provider<AutomateApiClient>(
                create: (_) => AutomateApiClient(auth),
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
  error,         // Error occurred
}

class _AutomateAuthGateState extends State<_AutomateAuthGate> {
  _AuthState _state = _AuthState.checking;
  String? _errorMessage;
  bool _hasTriedAuth = false;

  // Aliyun SDK secret key
  static const _secretKey = 'Fc9xB89wBqq7tuq8i0iMIvo5BHWoUj5M775f+2dvooScxIqhsragIsckpislAhTLHUcyfi7dLcTA7EQ6yqMtadLpXLWPQelBPeW6f2iHpz06CCuG832/fQonJj9A3+/Urw05pmL15jgwN7T2blb7KzX4nmOJaSsuuE29kt13KegyS83IoiqFNI+MTzWdig45BMkzEic8yFjynMpgFew77/T4s91GT/WrAf56x+ofUn4uOmRrvBeIUF9zWHhVz8jTyarWHsC+i79/l89zVrupL3LNJJfkreYdkI7b3RBqYhN1WYf0+7YzOPWPTNj7OxeM';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthState());
  }

  Future<void> _checkAuthState() async {
    final auth = context.read<AutomateAuthState>();
    final api = context.read<AutomateApiClient>();

    // Ensure auth state is loaded from storage before checking
    // This is critical because AutomateAuthState()..load() in Provider.create
    // does not wait for load() to complete (cascade operator returns immediately)
    await auth.load();

    debugPrint('[AuthGate] Checking auth state...');

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

      // Exchange token with backend
      final api = context.read<AutomateApiClient>();
      final authResponse = await api.loginOrSignup(
        '', // phone is empty for one-click login
        '', // code is empty for one-click login
        fusionToken: loginToken,
      );

      debugPrint('[AuthGate] Backend login success, onboardingCompleted=${authResponse.onboardingCompleted}');

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

      setState(() {
        _state = _AuthState.error;
        _errorMessage = _parseErrorMessage(errorStr);
      });
    }
  }

  String _parseErrorMessage(String error) {
    if (error.contains('预取号失败')) {
      return '网络环境不支持一键登录，请使用其他方式';
    }
    if (error.contains('SDK初始化失败')) {
      return '初始化失败，请检查网络连接';
    }
    return error.replaceAll('Exception: ', '');
  }

  Future<void> _loginMatrixAndProceed() async {
    final auth = context.read<AutomateAuthState>();
    final matrixAccessToken = auth.matrixAccessToken;
    final matrixUserId = auth.matrixUserId;

    if (matrixAccessToken == null || matrixUserId == null) {
      debugPrint('[AuthGate] Missing Matrix credentials for Matrix login');
      setState(() {
        _state = _AuthState.error;
        _errorMessage = 'Matrix 凭证缺失，请重新登录';
      });
      return;
    }

    try {
      final matrix = Matrix.of(context);
      final client = await matrix.getLoginClient();

      // Set homeserver before login
      final homeserverUrl = Uri.parse(AutomateConfig.matrixHomeserver);
      debugPrint('[AuthGate] Setting homeserver: $homeserverUrl');
      await client.checkHomeserver(homeserverUrl);

      debugPrint('[AuthGate] Attempting Matrix login: matrixUserId=$matrixUserId');

      // Use access_token directly (no password login needed)
      await client.init(
        newToken: matrixAccessToken,
        newUserID: matrixUserId,
        newHomeserver: homeserverUrl,
        newDeviceName: PlatformInfos.clientName,
      );
      debugPrint('[AuthGate] Matrix login success');

      setState(() => _state = _AuthState.authenticated);
      // Matrix login triggers auto navigation to /rooms
    } catch (e) {
      debugPrint('[AuthGate] Matrix login failed: $e');
      setState(() {
        _state = _AuthState.error;
        _errorMessage = 'Matrix 服务连接失败，请重试';
      });
    }
  }

  void _redirectToLoginPage() {
    setState(() => _state = _AuthState.needsLogin);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navKey = AutomateApp.router.routerDelegate.navigatorKey;
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

  void _navigateToOnboarding() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navKey = AutomateApp.router.routerDelegate.navigatorKey;
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
    final auth = context.watch<AutomateAuthState>();

    // If logged out externally, reset state
    if (!auth.isLoggedIn && _state == _AuthState.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _state = _AuthState.checking;
          _hasTriedAuth = false;
        });
        _checkAuthState();
      });
    }

    switch (_state) {
      case _AuthState.checking:
        // 检查 token 时不显示任何东西，保持原生启动画面
        // 这样 SDK 授权页弹出时用户不会看到中间的 loading
        return const SizedBox.shrink();

      case _AuthState.refreshing:
        return _buildLoadingScreen('正在验证登录状态...');

      case _AuthState.authenticating:
        return _buildLoadingScreen('正在登录...');

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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _state = _AuthState.checking;
                        _hasTriedAuth = false;
                      });
                      _checkAuthState();
                    },
                    child: const Text('重试'),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: _redirectToLoginPage,
                    child: const Text('其他登录方式'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
