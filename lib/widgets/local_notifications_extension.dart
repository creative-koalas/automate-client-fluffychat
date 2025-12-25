import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image/image.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

import 'package:psygo/config/setting_keys.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/aliyun_push_service.dart';
import 'package:psygo/utils/client_download_content_extension.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/push_helper.dart';
import 'package:psygo/utils/window_service.dart';
import 'package:psygo/widgets/fluffy_chat_app.dart';
import 'package:psygo/widgets/matrix.dart';

extension LocalNotificationsExtension on MatrixState {
  static final html.AudioElement _audioPlayer = html.AudioElement()
    ..src = 'assets/assets/sounds/notification.ogg'
    ..load();

  static FlutterLocalNotificationsPlugin? _flutterLocalNotificationsPlugin;
  static bool _isInitialized = false;

  Future<FlutterLocalNotificationsPlugin> _getNotificationsPlugin() async {
    if (_flutterLocalNotificationsPlugin != null && _isInitialized) {
      return _flutterLocalNotificationsPlugin!;
    }

    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    InitializationSettings? initSettings;
    if (Platform.isWindows) {
      final iconUri = WindowsImage.getAssetUri('assets/logo.png');
      initSettings = InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'Psygo',
          appUserModelId: 'com.psygo.app',
          guid: '8af2f2bb-4f08-4ac1-824e-977080f91d42',
          iconPath: iconUri.toFilePath(),
        ),
      );
    } else if (Platform.isMacOS) {
      initSettings = const InitializationSettings(
        macOS: DarwinInitializationSettings(),
      );
    }

    if (initSettings != null) {
      await _flutterLocalNotificationsPlugin!.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) async {
          final roomId = response.payload;
          if (roomId != null && roomId.isNotEmpty) {
            await WindowService.showWindow();
            PsygoApp.router.go('/rooms/$roomId');
          }
        },
      );
      _isInitialized = true;
    }

    return _flutterLocalNotificationsPlugin!;
  }

  void showLocalNotification(Event event) async {
    final roomId = event.room.id;
    // 如果用户在当前房间，不显示通知
    if (activeRoomId == roomId) {
      if (kIsWeb && webHasFocus) return;
      if (PlatformInfos.isDesktop &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
      // 移动端：App 在前台且在当前房间时不显示通知
      if ((Platform.isAndroid || Platform.isIOS) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    final title =
        event.room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final body = await event.calcLocalizedBody(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix: !event.room.isDirectChat ||
          event.room.lastEvent?.senderId == client.userID,
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );

    if (kIsWeb) {
      final avatarUrl = event.senderFromMemoryOrFallback.avatarUrl;
      Uri? thumbnailUri;

      if (avatarUrl != null) {
        const size = 128;
        const thumbnailMethod = ThumbnailMethod.crop;
        // Pre-cache so that we can later just set the thumbnail uri as icon:
        try {
          await client.downloadMxcCached(
            avatarUrl,
            width: size,
            height: size,
            thumbnailMethod: thumbnailMethod,
            isThumbnail: true,
            rounded: true,
          );
        } catch (e, s) {
          Logs().d('Unable to pre-download avatar for web notification', e, s);
        }

        thumbnailUri =
            await event.senderFromMemoryOrFallback.avatarUrl?.getThumbnailUri(
          client,
          width: size,
          height: size,
          method: thumbnailMethod,
        );
      }

      _audioPlayer.play();

      html.Notification(
        title,
        body: body,
        icon: thumbnailUri?.toString(),
        tag: event.room.id,
      );
    } else if (Platform.isLinux) {
      final avatarUrl = event.room.avatar;
      final hints = [NotificationHint.soundName('message-new-instant')];

      if (avatarUrl != null) {
        const size = notificationAvatarDimension;
        const thumbnailMethod = ThumbnailMethod.crop;
        // Pre-cache so that we can later just set the thumbnail uri as icon:
        final data = await client.downloadMxcCached(
          avatarUrl,
          width: size,
          height: size,
          thumbnailMethod: thumbnailMethod,
          isThumbnail: true,
          rounded: true,
        );

        final image = decodeImage(data);
        if (image != null) {
          final realData = image.getBytes(order: ChannelOrder.rgba);
          hints.add(
            NotificationHint.imageData(
              image.width,
              image.height,
              realData,
              hasAlpha: true,
              channels: 4,
            ),
          );
        }
      }
      final notification = await linuxNotifications!.notify(
        title,
        body: body,
        replacesId: linuxNotificationIds[roomId] ?? 0,
        appName: AppSettings.applicationName.value,
        appIcon: 'automate',
        actions: [
          NotificationAction(
            'default',
            L10n.of(context).openChat,
          ),
          NotificationAction(
            DesktopNotificationActions.seen.name,
            L10n.of(context).markAsRead,
          ),
        ],
        hints: hints,
      );
      notification.action.then((actionStr) async {
        if (actionStr == DesktopNotificationActions.seen.name) {
          event.room.setReadMarker(
            event.eventId,
            mRead: event.eventId,
            public: AppSettings.sendPublicReadReceipts.value,
          );
        } else {
          // 点击通知本身(default)或其他情况都跳转到聊天室
          await WindowService.showWindow();
          setActiveClient(event.room.client);
          PsygoApp.router.go('/rooms/${event.room.id}');
        }
      });
      linuxNotificationIds[roomId] = notification.id;
    } else if (Platform.isWindows || Platform.isMacOS) {
      final plugin = await _getNotificationsPlugin();

      NotificationDetails? notificationDetails;
      if (Platform.isWindows) {
        notificationDetails = NotificationDetails(
          windows: WindowsNotificationDetails(
            images: [
              WindowsImage(
                WindowsImage.getAssetUri('assets/logo.png'),
                altText: 'Psygo',
                placement: WindowsImagePlacement.appLogoOverride,
              ),
            ],
          ),
        );
      } else if (Platform.isMacOS) {
        notificationDetails = const NotificationDetails(
          macOS: DarwinNotificationDetails(
            sound: 'notification.caf',
          ),
        );
      }

      await plugin.show(
        roomId.hashCode,
        title,
        body,
        notificationDetails,
        payload: roomId,
      );
    } else if (Platform.isAndroid || Platform.isIOS) {
      // Android/iOS: 通过阿里云推送服务显示本地通知
      // 这里处理的是在线时 Matrix SDK 收到的消息
      // 离线时由 Push Gateway → 阿里云推送 → 厂商通道处理
      final unreadCount = client.rooms
          .where((r) => r.isUnreadOrInvited)
          .length;

      await AliyunPushService.instance.showNotificationForRoom(
        roomId: roomId,
        eventId: event.eventId,
        title: title,
        body: body,
        badge: unreadCount,
      );
    }
  }
}

enum DesktopNotificationActions { seen, openChat }
