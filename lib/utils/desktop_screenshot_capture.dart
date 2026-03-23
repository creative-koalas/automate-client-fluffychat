import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path_lib;

enum DesktopScreenshotCaptureStatus {
  success,
  cancelled,
  permissionDenied,
  failed,
}

class DesktopScreenshotCaptureResult {
  const DesktopScreenshotCaptureResult._({
    required this.status,
    this.file,
    this.error,
  });

  final DesktopScreenshotCaptureStatus status;
  final XFile? file;
  final Object? error;

  const DesktopScreenshotCaptureResult.success(XFile file)
    : this._(status: DesktopScreenshotCaptureStatus.success, file: file);

  const DesktopScreenshotCaptureResult.cancelled()
    : this._(status: DesktopScreenshotCaptureStatus.cancelled);

  const DesktopScreenshotCaptureResult.permissionDenied()
    : this._(status: DesktopScreenshotCaptureStatus.permissionDenied);

  const DesktopScreenshotCaptureResult.failed([Object? error])
    : this._(status: DesktopScreenshotCaptureStatus.failed, error: error);
}

class DesktopScreenshotCapture {
  const DesktopScreenshotCapture._();

  static const MethodChannel _channel = MethodChannel(
    'com.creativekoalas.psygo/macos_screenshot',
  );

  static Future<DesktopScreenshotCaptureResult> captureSelection() async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return const DesktopScreenshotCaptureResult.failed();
    }

    try {
      final filePath = await _channel.invokeMethod<String>(
        'captureScreenBuffer',
      );
      debugPrint('[Screenshot] captureScreenBuffer returned path: $filePath');
      if (filePath != null) {
        final screenshotFile = File(filePath);
        final hasImage =
            await screenshotFile.exists() && await screenshotFile.length() > 0;
        if (!hasImage) {
          debugPrint(
            '[Screenshot] Screen buffer file missing or empty: ${screenshotFile.path}',
          );
          return const DesktopScreenshotCaptureResult.failed();
        }
        return DesktopScreenshotCaptureResult.success(
          XFile(
            screenshotFile.path,
            name: path_lib.basename(screenshotFile.path),
            mimeType: 'image/png',
          ),
        );
      }
      debugPrint('[Screenshot] captureScreenBuffer returned null');
      return const DesktopScreenshotCaptureResult.failed();
    } on PlatformException catch (error) {
      debugPrint(
        '[Screenshot] PlatformException code=${error.code} message=${error.message} details=${error.details}',
      );
      if (error.code == 'PERMISSION_DENIED') {
        return const DesktopScreenshotCaptureResult.permissionDenied();
      }
      if (error.code == 'USER_CANCELLED') {
        return const DesktopScreenshotCaptureResult.cancelled();
      }
      return DesktopScreenshotCaptureResult.failed(error);
    } catch (error) {
      debugPrint('[Screenshot] Unexpected capture error: $error');
      return DesktopScreenshotCaptureResult.failed(error);
    }
  }
}
