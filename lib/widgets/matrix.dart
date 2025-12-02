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
import 'package:url_launcher/url_launcher_string.dart';

import 'package:automate/l10n/l10n.dart';
import 'package:automate/utils/client_manager.dart';
import 'package:automate/utils/init_with_restore.dart';
import 'package:automate/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:automate/utils/platform_infos.dart';
import 'package:automate/utils/uia_request_manager.dart';
import 'package:automate/utils/voip_plugin.dart';
import 'package:automate/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:automate/widgets/fluffy_chat_app.dart';
import 'package:automate/widgets/future_loading_dialog.dart';
import '../config/setting_keys.dart';
import '../pages/key_verification/key_verification_dialog.dart';
import '../utils/account_bundles.dart';
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
  String? activeBundle;

  SharedPreferences get store => widget.store;

  XFile? loginAvatar;
  String? loginUsername;
  bool? loginRegistrationSupported;

  BackgroundPush? backgroundPush;

  Client get client {
    if (_activeClient < 0 || _activeClient >= widget.clients.length) {
      return currentBundle!.first!;
    }
    return widget.clients[_activeClient];
  }

  VoipPlugin? voipPlugin;

  bool get isMultiAccount => widget.clients.length > 1;

  int getClientIndexByMatrixId(String matrixId) =>
      widget.clients.indexWhere((client) => client.userID == matrixId);

  late String currentClientSecret;
  RequestTokenResponse? currentThreepidCreds;

  void setActiveClient(Client? cl) {
    final i = widget.clients.indexWhere((c) => c == cl);
    if (i != -1) {
      _activeClient = i;
      // TODO: Multi-client VoiP support
      createVoipPlugin();
    } else {
      Logs().w('Tried to set an unknown client ${cl!.userID} as active');
    }
  }

  List<Client?>? get currentBundle {
    if (!hasComplexBundles) {
      return List.from(widget.clients);
    }
    final bundles = accountBundles;
    if (bundles.containsKey(activeBundle)) {
      return bundles[activeBundle];
    }
    return bundles.values.first;
  }

  Map<String?, List<Client?>> get accountBundles {
    final resBundles = <String?, List<_AccountBundleWithClient>>{};
    for (var i = 0; i < widget.clients.length; i++) {
      final bundles = widget.clients[i].accountBundles;
      for (final bundle in bundles) {
        if (bundle.name == null) {
          continue;
        }
        resBundles[bundle.name] ??= [];
        resBundles[bundle.name]!.add(
          _AccountBundleWithClient(
            client: widget.clients[i],
            bundle: bundle,
          ),
        );
      }
    }
    for (final b in resBundles.values) {
      b.sort(
        (a, b) => a.bundle!.priority == null
            ? 1
            : b.bundle!.priority == null
                ? -1
                : a.bundle!.priority!.compareTo(b.bundle!.priority!),
      );
    }
    return resBundles
        .map((k, v) => MapEntry(k, v.map((vv) => vv.client).toList()));
  }

  bool get hasComplexBundles => accountBundles.values.any((v) => v.length > 1);

  Client? _loginClientCandidate;

  AudioPlayer? audioPlayer;
  final ValueNotifier<String?> voiceMessageEventId = ValueNotifier(null);

  Future<Client> getLoginClient() async {
    if (widget.clients.isNotEmpty && !client.isLogged()) {
      return client;
    }
    final candidate =
        _loginClientCandidate ??= await ClientManager.createClient(
      '${AppSettings.applicationName.value}-${DateTime.now().millisecondsSinceEpoch}',
      store,
    )
          ..onLoginStateChanged
              .stream
              .where((l) => l == LoginState.loggedIn)
              .first
              .then((_) {
            if (!widget.clients.contains(_loginClientCandidate)) {
              widget.clients.add(_loginClientCandidate!);
            }
            ClientManager.addClientNameToStore(
              _loginClientCandidate!.clientName,
              store,
            );
            _registerSubs(_loginClientCandidate!.clientName);
            _loginClientCandidate = null;
            AutomateApp.router.go('/rooms');
          });
    if (widget.clients.isEmpty) widget.clients.add(candidate);
    return candidate;
  }

  Client? getClientByName(String name) =>
      widget.clients.firstWhereOrNull((c) => c.clientName == name);

  final onRoomKeyRequestSub = <String, StreamSubscription>{};
  final onKeyVerificationRequestSub = <String, StreamSubscription>{};
  final onNotification = <String, StreamSubscription>{};
  final onLoginStateChanged = <String, StreamSubscription<LoginState>>{};
  final onUiaRequest = <String, StreamSubscription<UiaRequest>>{};
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
    final route = AutomateApp.router.routeInformationProvider.value.uri.path;
    if (!route.startsWith('/rooms/')) return null;
    return route.split('/')[2];
  }

  final linuxNotifications =
      PlatformInfos.isLinux ? NotificationsClient() : null;
  final Map<String, int> linuxNotificationIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initMatrix();
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
          AutomateApp.router.pop('dialog');
        }
        hidPopup = true;
      };
      request.onUpdate = null;
      hidPopup = true;
      await KeyVerificationDialog(request: request).show(
        AutomateApp.router.routerDelegate.navigatorKey.currentContext ??
            context,
      );
    });
    onLoginStateChanged[name] ??= c.onLoginStateChanged.stream.listen((state) {
      final loggedInWithMultipleClients = widget.clients.length > 1;
      if (state == LoginState.loggedOut) {
        _cancelSubs(c.clientName);
        widget.clients.remove(c);
        ClientManager.removeClientNameFromStore(c.clientName, store);
        InitWithRestoreExtension.deleteSessionBackup(name);
      }
      // 登录成功后只注册推送（权限请求移到登录页面，确保时序正确）
      if (state == LoginState.loggedIn && PlatformInfos.isMobile) {
        _registerAliyunPushAfterLogin(c);
      }
      if (loggedInWithMultipleClients && state != LoginState.loggedIn) {
        ScaffoldMessenger.of(
          AutomateApp.router.routerDelegate.navigatorKey.currentContext ??
              context,
        ).showSnackBar(
          SnackBar(
            content: Text(L10n.of(context).oneClientLoggedOut),
          ),
        );

        if (state != LoginState.loggedIn) {
          AutomateApp.router.go('/rooms');
        }
      } else {
        AutomateApp.router
            .go(state == LoginState.loggedIn ? '/rooms' : '/home');
      }
    });
    onUiaRequest[name] ??= c.onUiaRequest.stream.listen(uiaRequestHandler);
    if (PlatformInfos.isWeb || PlatformInfos.isLinux) {
      c.onSync.stream.first.then((s) {
        html.Notification.requestPermission();
        onNotification[name] ??=
            c.onNotification.stream.listen(showLocalNotification);
      });
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
  }

  void initMatrix() {
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
      //       context: AutomateApp
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
      _initAliyunPush();
    }

    createVoipPlugin();
  }

  void createVoipPlugin() async {
    if (AppSettings.experimentalVoip.value) {
      voipPlugin = null;
      return;
    }
    voipPlugin = VoipPlugin(this);
  }

  /// 初始化阿里云推送
  Future<void> _initAliyunPush() async {
    try {
      // 设置回调函数（必须在 initialize 之前设置）
      // 1. 获取当前活跃房间 ID（用于判断是否显示通知）
      AliyunPushService.instance.activeRoomIdGetter = () => activeRoomId;

      // 2. 通知点击回调（导航到对应房间）
      AliyunPushService.instance.onNotificationTapped = (roomId, eventId) {
        Logs().i('[Matrix] Notification tapped: room=$roomId, event=$eventId');
        AutomateApp.router.go('/rooms/$roomId');
      };

      final success = await AliyunPushService.instance.initialize();
      if (success) {
        Logs().i('[Matrix] Aliyun Push initialized successfully');

        // 如果用户已登录
        if (client.isLogged() && client.userID != null) {
          // 绑定账号用于精准推送
          await AliyunPushService.instance.bindAccount(client.userID!);

          // 注册推送到后端和 Synapse
          final pushRegistered = await AliyunPushService.instance.registerPush(client);
          if (pushRegistered) {
            Logs().i('[Matrix] Push registration completed');
          } else {
            Logs().w('[Matrix] Push registration failed');
          }
        }
      } else {
        Logs().w('[Matrix] Aliyun Push initialization failed');
      }
    } catch (e, s) {
      Logs().e('[Matrix] Aliyun Push init error', e, s);
    }
  }

  /// 登录成功后注册阿里云推送
  Future<void> _registerAliyunPushAfterLogin(Client c) async {
    try {
      Logs().i('[Matrix] Registering Aliyun Push after login for ${c.userID}');

      // 确保 SDK 已初始化
      if (!AliyunPushService.instance.isInitialized) {
        final initSuccess = await AliyunPushService.instance.initialize();
        if (!initSuccess) {
          Logs().w('[Matrix] Aliyun Push SDK initialization failed');
          return;
        }
      }

      // 检查是否有 deviceId
      if (AliyunPushService.instance.deviceId == null) {
        Logs().w('[Matrix] Aliyun Push deviceId is null, cannot register');
        return;
      }

      final userID = c.userID;
      if (userID == null) {
        Logs().w('[Matrix] User ID is null, cannot register push');
        return;
      }

      // 绑定账号用于精准推送
      await AliyunPushService.instance.bindAccount(userID);

      // 注册推送到后端和 Synapse
      final pushRegistered = await AliyunPushService.instance.registerPush(c);
      if (pushRegistered) {
        Logs().i('[Matrix] Push registration completed for $userID');
      } else {
        Logs().w('[Matrix] Push registration failed for $userID');
      }
    } catch (e, s) {
      Logs().e('[Matrix] Register Aliyun Push after login error', e, s);
    }
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    onRoomKeyRequestSub.values.map((s) => s.cancel());
    onKeyVerificationRequestSub.values.map((s) => s.cancel());
    onLoginStateChanged.values.map((s) => s.cancel());
    onNotification.values.map((s) => s.cancel());
    client.httpClient.close();
    onFocusSub?.cancel();
    onBlurSub?.cancel();

    linuxNotifications?.close();

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

class _AccountBundleWithClient {
  final Client? client;
  final AccountBundle? bundle;

  _AccountBundleWithClient({this.client, this.bundle});
}
