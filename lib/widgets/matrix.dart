import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;
import 'package:window_manager/window_manager.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/client_manager.dart';
import 'package:psygo/utils/init_with_restore.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/post_login_navigation.dart';
import 'package:psygo/utils/push_state_reporter.dart';
import 'package:psygo/utils/uia_request_manager.dart';
import 'package:psygo/utils/voip_plugin.dart';
import 'package:psygo/utils/window_service.dart';
import 'package:psygo/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:psygo/widgets/fluffy_chat_app.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/layouts/desktop_layout.dart';
import 'package:psygo/widgets/mxc_image.dart';
import '../config/setting_keys.dart';
import '../pages/key_verification/key_verification_dialog.dart';
import '../services/agent_service.dart';
import '../utils/aliyun_push_service.dart';
import '../utils/background_push.dart';
import 'local_notifications_extension.dart';

// import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Matrix extends StatefulWidget {
  final Widget? child;

  final List<Client> clients;

  final Map<String, String>? queryParameters;

  final SharedPreferences store;

  const Matrix({
    this.child,
    required this.clients,
    required this.store,
    this.queryParameters,
    super.key,
  });

  @override
  MatrixState createState() => MatrixState();

  /// Returns the (nearest) Client instance of your application.
  static MatrixState of(BuildContext context) =>
      Provider.of<MatrixState>(context, listen: false);
}

class MatrixState extends State<Matrix> with WidgetsBindingObserver {
  int _activeClient = -1;

  SharedPreferences get store => widget.store;

  XFile? loginAvatar;
  String? loginUsername;
  bool? loginRegistrationSupported;

  BackgroundPush? backgroundPush;

  /// Returns the currently active Matrix client.
  ///
  /// Returns null if no clients are available (e.g., during first-time login
  /// before the client is fully initialized and added to the list).
  Client? get clientOrNull {
    if (widget.clients.isEmpty) {
      return null;
    }
    if (_activeClient < 0 || _activeClient >= widget.clients.length) {
      return widget.clients.first;
    }
    return widget.clients[_activeClient];
  }

  /// Returns the currently active Matrix client.
  ///
  /// Throws [StateError] if no clients are available. Prefer using [clientOrNull]
  /// in contexts where the client might not be initialized yet.
  Client get client {
    final c = clientOrNull;
    if (c == null) {
      throw StateError(
        'No Matrix client available. This usually happens during first-time login '
        'before the client is fully initialized. Use clientOrNull for null-safe access.',
      );
    }
    return c;
  }

  VoipPlugin? voipPlugin;

  bool get isMultiAccount => widget.clients.length > 1;

  int getClientIndexByMatrixId(String matrixId) =>
      widget.clients.indexWhere((client) => client.userID == matrixId);

  late String currentClientSecret;
  RequestTokenResponse? currentThreepidCreds;

  void setActiveClient(Client? cl) {
    if (cl == null) return;

    var i = widget.clients.indexWhere((c) => identical(c, cl));
    if (i == -1) {
      i = widget.clients.indexWhere((c) => c.clientName == cl.clientName);
    }
    if (i == -1 && cl.userID != null) {
      i = widget.clients.indexWhere((c) => c.userID == cl.userID);
    }

    if (i != -1) {
      _activeClient = i;
      // TODO: Multi-client VoiP support
      createVoipPlugin();
    } else {
      Logs().w('Tried to set an unknown client ${cl.userID} as active');
    }
  }

  List<Client> get currentBundle => widget.clients;

  Map<String?, List<Client?>> get accountBundles => {
        null: widget.clients,
      };

  bool get hasComplexBundles => false;

  Client? _loginClientCandidate;

  AudioPlayer? audioPlayer;
  final ValueNotifier<String?> voiceMessageEventId = ValueNotifier(null);

  Future<Client> getLoginClient() async {
    debugPrint(
        '[Matrix] getLoginClient called, clients.length=${widget.clients.length}');
    if (widget.clients.isNotEmpty) {
      debugPrint('[Matrix] Returning existing single-slot client');
      return client;
    }
    final candidate =
        _loginClientCandidate ??= await ClientManager.createClient(
      ClientManager.defaultSingleClientName,
      store,
    )
          ..onLoginStateChanged
              .stream
              .where((l) => l == LoginState.loggedIn)
              .first
              .then((_) {
            debugPrint(
                '[Matrix] onLoginStateChanged: loggedIn, adding client to list');
            if (!widget.clients.contains(_loginClientCandidate)) {
              widget.clients.add(_loginClientCandidate!);
              debugPrint(
                  '[Matrix] Client added via onLoginStateChanged, clients.length=${widget.clients.length}');
            }
            // 设置新登录的客户端为活跃客户端
            _activeClient = widget.clients.indexOf(_loginClientCandidate!);
            debugPrint('[Matrix] Set activeClient to $_activeClient');
            ClientManager.addClientNameToStore(
              _loginClientCandidate!.clientName,
              store,
            );
            _registerSubs(_loginClientCandidate!.clientName);
            _loginClientCandidate = null;
            unawaited(() async {
              final destination = await resolvePostLoginDestination(
                currentPath: PsygoApp.router.routeInformationProvider.value.uri.path,
              );
              PsygoApp.router.go(destination);
            }());
          });
    debugPrint(
        '[Matrix] Before adding candidate: clients.isEmpty=${widget.clients.isEmpty}');
    if (widget.clients.isEmpty) {
      widget.clients.add(candidate);
      debugPrint(
          '[Matrix] Candidate added to clients list, clients.length=${widget.clients.length}');
    }
    debugPrint(
        '[Matrix] getLoginClient returning, clients.length=${widget.clients.length}');
    return candidate;
  }

  Client? getClientByName(String name) =>
      widget.clients.firstWhereOrNull((c) => c.clientName == name);

  final onRoomKeyRequestSub = <String, StreamSubscription>{};
  final onKeyVerificationRequestSub = <String, StreamSubscription>{};
  final onNotification = <String, StreamSubscription>{};
  final onTimelineEventSub = <String, StreamSubscription<Event>>{};
  final Set<String> _desktopNotifiedEventIds = <String>{};
  static const int _desktopNotificationCacheLimit = 200;
  final onLoginStateChanged = <String, StreamSubscription<LoginState>>{};
  final onUiaRequest = <String, StreamSubscription<UiaRequest>>{};
  final Map<String, Future<void>> _pushRegistrationTasks = {};
  StreamSubscription<html.Event>? onFocusSub;
  StreamSubscription<html.Event>? onBlurSub;

  String? _cachedPassword;
  Timer? _cachedPasswordClearTimer;

  String? get cachedPassword => _cachedPassword;

  set cachedPassword(String? p) {
    Logs().d('Password cached');
    _cachedPasswordClearTimer?.cancel();
    _cachedPassword = p;
    _cachedPasswordClearTimer = Timer(const Duration(minutes: 10), () {
      _cachedPassword = null;
      Logs().d('Cached Password cleared');
    });
  }

  bool webHasFocus = true;

  String? get activeRoomId {
    final route = PsygoApp.router.routeInformationProvider.value.uri.path;
    if (!route.startsWith('/rooms/')) return null;
    return route.split('/')[2];
  }

  void _onRouteChanged() {
    _updatePushState();
  }

  void _updatePushState() {
    if (!PlatformInfos.isMobile) return;
    final currentClient = clientOrNull;
    if (currentClient == null || !currentClient.isLogged()) return;
    final matrixUserId = currentClient.userID;
    if (matrixUserId == null || matrixUserId.isEmpty) return;

    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final isForeground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;

    PushStateReporter.instance.updateState(
      isForeground: isForeground,
      activeRoomId: activeRoomId,
      matrixUserId: matrixUserId,
      deviceId: AliyunPushService.instance.deviceId,
      pushKey: AliyunPushService.instance.pushKey,
    );
  }

  NotificationsClient? _linuxNotifications;

  NotificationsClient? get linuxNotifications {
    if (!PlatformInfos.isLinux) return null;
    _linuxNotifications ??= NotificationsClient();
    return _linuxNotifications;
  }

  void resetLinuxNotifications() {
    if (!PlatformInfos.isLinux) return;
    try {
      _linuxNotifications?.close();
    } catch (_) {}
    _linuxNotifications = NotificationsClient();
  }

  final Map<String, int> linuxNotificationIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (PlatformInfos.isMobile) {
      PsygoApp.router.routeInformationProvider.addListener(_onRouteChanged);
    }
    initMatrix();
    _updatePushState();
  }

  /// Ensure a client is present in the bundle and its subscriptions are active.
  /// Returns true if the client was newly added to the bundle.
  bool ensureClientRegistered(Client c) {
    final exists =
        widget.clients.any((client) => client.clientName == c.clientName);
    if (!exists) {
      widget.clients.add(c);
    }
    _registerSubs(c.clientName);
    return !exists;
  }

  void _registerSubs(String name) {
    final c = getClientByName(name);
    if (c == null) {
      Logs().w(
        'Attempted to register subscriptions for non-existing client $name',
      );
      return;
    }
    onRoomKeyRequestSub[name] ??=
        c.onRoomKeyRequest.stream.listen((RoomKeyRequest request) async {
      if (widget.clients.any(
        ((cl) =>
            cl.userID == request.requestingDevice.userId &&
            cl.identityKey == request.requestingDevice.curve25519Key),
      )) {
        Logs().i(
          '[Key Request] Request is from one of our own clients, forwarding the key...',
        );
        await request.forwardKey();
      }
    });
    onKeyVerificationRequestSub[name] ??= c.onKeyVerificationRequest.stream
        .listen((KeyVerification request) async {
      var hidPopup = false;
      request.onUpdate = () {
        if (!hidPopup &&
            {KeyVerificationState.done, KeyVerificationState.error}
                .contains(request.state)) {
          PsygoApp.router.pop('dialog');
        }
        hidPopup = true;
      };
      request.onUpdate = null;
      hidPopup = true;
      await KeyVerificationDialog(request: request).show(
        PsygoApp.router.routerDelegate.navigatorKey.currentContext ?? context,
      );
    });
    onLoginStateChanged[name] ??= c.onLoginStateChanged.stream.listen((state) {
      final loggedInWithMultipleClients = widget.clients.length > 1;
      if (state == LoginState.loggedOut) {
        // 注销推送（防止登出后仍收到推送、防止换号后收到上一个用户的推送）
        if (PlatformInfos.isMobile) {
          final loggedOutUserId = c.userID;
          if (loggedOutUserId != null && loggedOutUserId.isNotEmpty) {
            AliyunPushService.instance
                .clearRegisterPushStateForUser(loggedOutUserId);
          }
          final pushKey = AliyunPushService.instance.pushKey;
          if (pushKey != null) {
            AliyunPushService.instance.clearRegisterPushStateByPushKey(pushKey);
            _pushAudit('unregister start pushKey=$pushKey');
            unawaited(AliyunPushService.instance.unregisterPush(pushKey));
          }
          PushStateReporter.instance.stop();
        }

        _cancelSubs(c.clientName);
        widget.clients.remove(c);
        ClientManager.removeClientNameFromStore(c.clientName, store);
        InitWithRestoreExtension.deleteSessionBackup(name);

        // 清除图片缓存和用户信息缓存，避免显示旧用户的头像
        MxcImage.clearCache();
        DesktopLayout.clearUserCache();

        // 重置状态，确保下次登录使用新的 client
        _activeClient = widget.clients.isNotEmpty ? 0 : -1;
        _loginClientCandidate = null;
      }
      // 登录成功后注册推送和刷新员工列表
      if (state == LoginState.loggedIn) {
        // 刷新员工列表缓存（登录后才有 token）
        AgentService.instance.refresh();
        // 移动端注册推送
        if (PlatformInfos.isMobile && !_skipAliyunPushOnCurrentDevice) {
          unawaited(ensureAliyunPushRegistered(c));
        }
        _updatePushState();
      }
      if (loggedInWithMultipleClients && state == LoginState.loggedOut) {
        ScaffoldMessenger.of(
          PsygoApp.router.routerDelegate.navigatorKey.currentContext ?? context,
        ).showSnackBar(
          SnackBar(
            content: Text(L10n.of(context).oneClientLoggedOut),
          ),
        );

        PsygoApp.router.go('/rooms');
      } else {
        // Mobile: Don't redirect to /login-signup, let AuthGate handle
        // Web/Desktop: Redirect to /login-signup for manual login
        if (state == LoginState.loggedIn) {
          unawaited(() async {
            final destination = await resolvePostLoginDestination(
              currentPath: PsygoApp.router.routeInformationProvider.value.uri.path,
            );
            PsygoApp.router.go(destination);
          }());
        } else {
          final destination = PlatformInfos.isMobile ? '/' : '/login-signup';
          PsygoApp.router.go(destination);
        }
      }
    });
    onUiaRequest[name] ??= c.onUiaRequest.stream.listen(uiaRequestHandler);
    if (PlatformInfos.isWeb) {
      unawaited(
        c.onSync.stream.first.then((_) {
          html.Notification.requestPermission();
        }),
      );
    }
    // 移动端不订阅 Matrix SDK 的通知事件，由阿里云推送服务统一处理
    // 避免 Matrix SDK 本地通知和阿里云推送通知重复
    if (!PlatformInfos.isMobile) {
      onNotification[name] ??= c.onNotification.stream.listen((event) {
        if (PlatformInfos.isLinux) {
          Logs().i(
            '[LinuxNotify] onNotification room=${event.room.id} event=${event.eventId} type=${event.type}',
          );
        }
        if (PlatformInfos.isDesktop && _isDesktopEventNotified(event)) {
          return;
        }
        if (PlatformInfos.isDesktop) {
          _trackDesktopNotifiedEvent(event);
        }
        showLocalNotification(event);
      });
      if (PlatformInfos.isDesktop) {
        onTimelineEventSub[name] ??= c.onTimelineEvent.stream.listen((event) {
          // ignore: discarded_futures
          _handleDesktopBackgroundNotification(c, event);
        });
      }
    }
  }

  void _cancelSubs(String name) {
    onRoomKeyRequestSub[name]?.cancel();
    onRoomKeyRequestSub.remove(name);
    onKeyVerificationRequestSub[name]?.cancel();
    onKeyVerificationRequestSub.remove(name);
    onLoginStateChanged[name]?.cancel();
    onLoginStateChanged.remove(name);
    onNotification[name]?.cancel();
    onNotification.remove(name);
    onTimelineEventSub[name]?.cancel();
    onTimelineEventSub.remove(name);
  }

  static const Set<String> _desktopNotifyEventTypes = {
    EventTypes.Message,
    EventTypes.Sticker,
    EventTypes.Encrypted,
  };

  bool _isDesktopEventNotified(Event event) {
    final eventId = event.eventId;
    return _desktopNotifiedEventIds.contains(eventId);
  }

  void _trackDesktopNotifiedEvent(Event event) {
    final eventId = event.eventId;
    _desktopNotifiedEventIds.add(eventId);
    while (_desktopNotifiedEventIds.length > _desktopNotificationCacheLimit) {
      _desktopNotifiedEventIds.remove(_desktopNotifiedEventIds.first);
    }
  }

  Future<void> _handleDesktopBackgroundNotification(
      Client c, Event event) async {
    if (!PlatformInfos.isDesktop) return;
    if (event.senderId == c.userID) return;
    if (!_desktopNotifyEventTypes.contains(event.type)) return;
    if (event.relationshipType == RelationshipTypes.edit) return;
    if (!await _isDesktopInBackground()) return;
    if (_isDesktopEventNotified(event)) return;
    _trackDesktopNotifiedEvent(event);
    if (PlatformInfos.isLinux) {
      Logs().i(
        '[LinuxNotify] background notify room=${event.room.id} event=${event.eventId} type=${event.type}',
      );
    }
    showLocalNotification(event);
  }

  Future<bool> _isDesktopInBackground() async {
    if (WindowService.isHiddenToTray) {
      return true;
    }
    try {
      final isVisible = await windowManager.isVisible();
      final isFocused = await windowManager.isFocused();
      final isMinimized = await windowManager.isMinimized();
      return !(isVisible && isFocused && !isMinimized);
    } catch (e, s) {
      Logs().w(
          '[Matrix] Unable to query window state for desktop notifications',
          e,
          s);
      return true;
    }
  }

  bool get _skipAliyunPushOnCurrentDevice => PlatformInfos.isIOSSimulator;

  void initMatrix() {
    if (PlatformInfos.isDesktop) {
      unawaited(warmupDesktopNotifications());
    }

    // 设置活跃客户端：优先选择已登录的客户端
    if (widget.clients.isNotEmpty) {
      final loggedInIndex = widget.clients.indexWhere((c) => c.isLogged());
      _activeClient = loggedInIndex >= 0 ? loggedInIndex : 0;
      debugPrint(
          '[Matrix] initMatrix: Set activeClient to $_activeClient (userID: ${widget.clients[_activeClient].userID})');
    }

    for (final c in widget.clients) {
      _registerSubs(c.clientName);
    }

    if (kIsWeb) {
      onFocusSub = html.window.onFocus.listen((_) => webHasFocus = true);
      onBlurSub = html.window.onBlur.listen((_) => webHasFocus = false);
    }

    if (PlatformInfos.isMobile) {
      // 注意：我们使用阿里云推送，禁用 FluffyChat 原有的 BackgroundPush（Firebase/UnifiedPush）
      // 避免两套推送系统同时注册 pusher 到 Synapse 导致重复推送
      // backgroundPush = BackgroundPush(
      //   this,
      //   onFcmError: (errorMsg, {Uri? link}) async {
      //     final result = await showOkCancelAlertDialog(
      //       context: PsygoApp
      //               .router.routerDelegate.navigatorKey.currentContext ??
      //           context,
      //       title: L10n.of(context).pushNotificationsNotAvailable,
      //       message: errorMsg,
      //       okLabel:
      //           link == null ? L10n.of(context).ok : L10n.of(context).learnMore,
      //       cancelLabel: L10n.of(context).doNotShowAgain,
      //     );
      //     if (result == OkCancelResult.ok && link != null) {
      //       launchUrlString(
      //         link.toString(),
      //         mode: LaunchMode.externalApplication,
      //       );
      //     }
      //     if (result == OkCancelResult.cancel) {
      //       await AppSettings.showNoGoogle.setItem(true);
      //     }
      //   },
      // );

      // 初始化阿里云推送（唯一的推送渠道）
      if (_skipAliyunPushOnCurrentDevice) {
        Logs().i(
            '[Matrix] iOS simulator detected, skipping Aliyun Push initialization');
      } else {
        _initAliyunPush();
      }
    }

    createVoipPlugin();

    // 初始化员工服务（加载员工列表缓存）
    AgentService.instance.init();
  }

  void createVoipPlugin() async {
    if (AppSettings.experimentalVoip.value) {
      voipPlugin = null;
      return;
    }
    // 如果没有可用的 client，跳过 VoIP 插件创建
    if (clientOrNull == null) {
      voipPlugin = null;
      return;
    }
    voipPlugin = VoipPlugin(this);
  }

  /// 初始化阿里云推送 SDK
  ///
  /// 只负责 SDK 初始化和回调设置，不做推送注册。
  /// 注册统一由 [ensureAliyunPushRegistered] 在登录成功后触发。
  Future<void> _initAliyunPush() async {
    if (_skipAliyunPushOnCurrentDevice) {
      Logs().i('[Matrix] iOS simulator detected, skip _initAliyunPush');
      return;
    }
    try {
      // 设置回调函数（必须在 initialize 之前设置）
      AliyunPushService.instance.activeRoomIdGetter = () => activeRoomId;
      AliyunPushService.instance.currentUserIdGetter =
          () => clientOrNull?.userID;
      AliyunPushService.instance.onNotificationTapped = (roomId, eventId) {
        Logs().i('[Matrix] Notification tapped: room=$roomId, event=$eventId');
        PsygoApp.router.go('/rooms/$roomId');
      };

      final success = await AliyunPushService.instance.initialize();
      if (success) {
        Logs().i('[Matrix] Aliyun Push SDK initialized');
      } else {
        Logs().w('[Matrix] Aliyun Push SDK initialization failed');
      }
    } catch (e, s) {
      Logs().e('[Matrix] Aliyun Push init error', e, s);
    }
  }

  Future<void> ensureAliyunPushRegistered(Client c) async {
    if (!PlatformInfos.isMobile) return;
    final userID = c.userID;
    if (userID == null || userID.isEmpty) return;
    if (!AliyunPushService.instance.shouldAttemptRegister(userID)) return;

    final inFlightTask = _pushRegistrationTasks[userID];
    if (inFlightTask != null) {
      await inFlightTask;
      return;
    }

    final task = _registerAliyunPushAfterLogin(c);
    _pushRegistrationTasks[userID] = task;
    try {
      await task;
    } finally {
      if (identical(_pushRegistrationTasks[userID], task)) {
        _pushRegistrationTasks.remove(userID);
      }
    }
  }

  /// 登录成功后注册阿里云推送
  Future<void> _registerAliyunPushAfterLogin(Client c) async {
    if (_skipAliyunPushOnCurrentDevice) {
      Logs().i(
          '[Matrix] iOS simulator detected, skip push registration after login');
      return;
    }
    try {
      final userID = c.userID;
      if (userID == null) return;

      _pushAudit('register start user=$userID');

      // 确保 SDK 已初始化（首次登录时 _initAliyunPush 可能还未完成）
      if (!AliyunPushService.instance.isInitialized) {
        final initSuccess = await AliyunPushService.instance.initialize();
        if (!initSuccess) {
          _pushAudit('register abort: SDK init failed');
          return;
        }
      }

      // 绑定账号用于精准推送
      await AliyunPushService.instance.bindAccount(userID);

      // 注册推送到后端和 Synapse
      final ok = await AliyunPushService.instance.registerPush(c);
      _pushAudit('register ${ok ? 'ok' : 'failed'} user=$userID');
      _updatePushState();
    } catch (e, s) {
      _pushAudit('register exception $e');
      Logs().e('[Matrix] Push registration error', e, s);
    }
  }

  /// Release 模式审计日志
  void _pushAudit(String message) {
    if (!kReleaseMode) return;
    // ignore: avoid_print
    print('[PUSH_AUDIT:Matrix] $message');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused;
    for (final client in widget.clients) {
      client.syncPresence =
          state == AppLifecycleState.resumed ? null : PresenceType.unavailable;
      if (PlatformInfos.isMobile) {
        client.backgroundSync = foreground;
        client.requestHistoryOnLimitedTimeline = !foreground;
        Logs().v('Set background sync to', foreground);
      }
    }

    // 补偿注册：App 回到前台时再尝试一次推送注册，降低 token 延迟/网络抖动导致的漏注册概率。
    if (state == AppLifecycleState.resumed &&
        PlatformInfos.isMobile &&
        !_skipAliyunPushOnCurrentDevice) {
      for (final c in widget.clients) {
        final userID = c.userID;
        if (c.isLogged() &&
            userID != null &&
            userID.isNotEmpty &&
            AliyunPushService.instance.shouldAttemptRegister(userID)) {
          unawaited(ensureAliyunPushRegistered(c));
        }
      }
    }

    _updatePushState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (PlatformInfos.isMobile) {
      PsygoApp.router.routeInformationProvider.removeListener(_onRouteChanged);
      PushStateReporter.instance.stop();
    }

    // 修复：使用 forEach 而不是 map，因为 map 是惰性的不会立即执行
    for (final sub in onRoomKeyRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onKeyVerificationRequestSub.values) {
      sub.cancel();
    }
    for (final sub in onLoginStateChanged.values) {
      sub.cancel();
    }
    for (final sub in onNotification.values) {
      sub.cancel();
    }
    for (final sub in onTimelineEventSub.values) {
      sub.cancel();
    }
    client.httpClient.close();
    onFocusSub?.cancel();
    onBlurSub?.cancel();
    voiceMessageEventId.dispose();

    _linuxNotifications?.close();
    _linuxNotifications = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (_) => this,
      child: widget.child,
    );
  }

  Future<void> dehydrateAction(BuildContext context) async {
    final response = await showOkCancelAlertDialog(
      context: context,
      isDestructive: true,
      title: L10n.of(context).dehydrate,
      message: L10n.of(context).dehydrateWarning,
    );
    if (response != OkCancelResult.ok) {
      return;
    }
    final result = await showFutureLoadingDialog(
      context: context,
      future: client.exportDump,
    );
    final export = result.result;
    if (export == null) return;

    final exportBytes = Uint8List.fromList(
      const Utf8Codec().encode(export),
    );

    final exportFileName =
        'automate-export-${DateFormat(DateFormat.YEAR_MONTH_DAY).format(DateTime.now())}.automatebackup';

    final file = MatrixFile(bytes: exportBytes, name: exportFileName);
    file.save(context);
  }
}
