import 'dart:async';

import 'package:flutter/services.dart';
import 'package:psygo/utils/platform_infos.dart';

class MacosGlobalScreenshotHotkey {
  MacosGlobalScreenshotHotkey._();

  static const MethodChannel _channel = MethodChannel(
    'com.creativekoalas.psygo/macos_global_screenshot_hotkey',
  );

  static bool _initialized = false;
  static bool _isHandling = false;
  static DateTime? _lastHandledAt;
  static const Duration _cooldown = Duration(milliseconds: 700);
  static Future<void> Function()? _handler;

  static Future<void> initialize() async {
    if (!PlatformInfos.isMacOS || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onHotKeyPressed') {
        throw MissingPluginException(
          'Unknown macOS screenshot hotkey method: ${call.method}',
        );
      }
      if (_handler == null) return;
      final now = DateTime.now();
      final lastHandledAt = _lastHandledAt;
      if (_isHandling) return;
      if (lastHandledAt != null && now.difference(lastHandledAt) < _cooldown) return;
      _isHandling = true;
      _lastHandledAt = now;
      try {
        await _handler?.call();
      } finally {
        _isHandling = false;
      }
    });
  }

  static void registerHandler(Future<void> Function() handler) {
    _handler = handler;
  }

  static void unregisterHandler(Future<void> Function() handler) {
    if (identical(_handler, handler)) {
      _handler = null;
    }
  }
}
