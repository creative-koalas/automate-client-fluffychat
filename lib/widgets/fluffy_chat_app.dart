import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/automate/backend/backend.dart';
import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import '../utils/custom_scroll_behaviour.dart';
import 'matrix.dart';

class FluffyChatApp extends StatelessWidget {
  final Widget? testWidget;
  final List<Client> clients;
  final String? pincode;
  final SharedPreferences store;

  const FluffyChatApp({
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
        builder: (context, child) => _AutomateAuthListener(
          child: AppLockWidget(
            pincode: pincode,
            clients: clients,
            // Need a navigator above the Matrix widget for
            // displaying dialogs
            child: Matrix(
              clients: clients,
              store: store,
              child: testWidget ?? child,
            ),
          ),
        ),
      ),
    );
  }
}

class _AutomateAuthListener extends StatefulWidget {
  final Widget? child;
  const _AutomateAuthListener({this.child});

  @override
  State<_AutomateAuthListener> createState() => _AutomateAuthListenerState();
}

class _AutomateAuthListenerState extends State<_AutomateAuthListener> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = AutomateAuthManager.instance.unauthorized.listen((_) async {
      await AutomateBackend.instance.clearTokens();
      _redirectToLogin();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();

  void _redirectToLogin() {
    final navKey = FluffyChatApp.router.routerDelegate.navigatorKey;
    final ctx = navKey.currentContext;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _redirectToLogin());
      return;
    }
    final navigator = navKey.currentState;
    navigator?.popUntil((route) => route.isFirst);

    final router = GoRouter.of(ctx);
    router.go('/login-signup');
  }
}
