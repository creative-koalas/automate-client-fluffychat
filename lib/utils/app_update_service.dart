import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:psygo/backend/api_client.dart';
import 'package:psygo/utils/platform_infos.dart';

/// 应用更新服务
class AppUpdateService {
  final PsygoApiClient _apiClient;

  AppUpdateService(this._apiClient);

  /// 检查更新并显示弹窗
  /// 返回 true 表示用户可以继续使用，false 表示被强制更新阻止
  Future<bool> checkAndPrompt(BuildContext context) async {
    try {
      final currentVersion = await PlatformInfos.getVersion();
      final platform = _getPlatformName();

      debugPrint('[AppUpdate] Checking update: version=$currentVersion, platform=$platform');

      final response = await _apiClient.checkAppVersion(
        currentVersion: currentVersion,
        platform: platform,
      );

      debugPrint('[AppUpdate] Response: hasUpdate=${response.hasUpdate}, forceUpdate=${response.forceUpdate}');

      if (!response.hasUpdate) {
        // 已是最新版本
        return true;
      }

      if (!context.mounted) return true;

      // 显示更新弹窗
      final shouldContinue = await showDialog<bool>(
        context: context,
        barrierDismissible: !response.forceUpdate,
        builder: (context) => _UpdateDialog(
          latestVersion: response.latestVersion,
          forceUpdate: response.forceUpdate,
          downloadUrl: response.downloadUrl!,
        ),
      );

      // 如果是强制更新且用户没有点击更新，返回 false
      if (response.forceUpdate && shouldContinue != true) {
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[AppUpdate] Check failed: $e');
      // 检查失败时不阻止用户使用
      return true;
    }
  }

  /// 获取平台名称
  String _getPlatformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}

/// 更新弹窗（支持下载进度）
class _UpdateDialog extends StatefulWidget {
  final String latestVersion;
  final bool forceUpdate;
  final String downloadUrl;

  const _UpdateDialog({
    required this.latestVersion,
    required this.forceUpdate,
    required this.downloadUrl,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdateState {
  idle,        // 等待用户点击
  downloading, // 下载中
  downloaded,  // 下载完成
  error,       // 下载失败
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _UpdateState _state = _UpdateState.idle;
  double _progress = 0;
  String? _errorMessage;
  String? _downloadedFilePath;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  /// 是否需要应用内下载（桌面端和 Android）
  bool get _needsInAppDownload {
    if (kIsWeb) return false;
    if (Platform.isIOS) return false; // iOS 必须跳转 App Store
    return true;
  }

  /// 获取下载文件名
  String _getFileName() {
    final uri = Uri.parse(widget.downloadUrl);
    final pathSegments = uri.pathSegments;
    if (pathSegments.isNotEmpty) {
      return pathSegments.last;
    }
    // 默认文件名
    if (Platform.isWindows) return 'psygo-setup.exe';
    if (Platform.isMacOS) return 'psygo.dmg';
    if (Platform.isLinux) return 'psygo.deb';
    if (Platform.isAndroid) return 'psygo.apk';
    return 'psygo-update';
  }

  /// 开始下载
  Future<void> _startDownload() async {
    setState(() {
      _state = _UpdateState.downloading;
      _progress = 0;
      _errorMessage = null;
    });

    try {
      // 获取下载目录
      final dir = await getTemporaryDirectory();
      final fileName = _getFileName();
      final filePath = '${dir.path}/$fileName';

      debugPrint('[AppUpdate] Downloading to: $filePath');

      _cancelToken = CancelToken();
      final dio = Dio();

      await dio.download(
        widget.downloadUrl,
        filePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      debugPrint('[AppUpdate] Download completed');

      setState(() {
        _state = _UpdateState.downloaded;
        _downloadedFilePath = filePath;
      });
    } catch (e) {
      debugPrint('[AppUpdate] Download failed: $e');
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // 用户取消
        setState(() {
          _state = _UpdateState.idle;
        });
      } else {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = '下载失败: $e';
        });
      }
    }
  }

  /// 取消下载
  void _cancelDownload() {
    _cancelToken?.cancel();
  }

  /// 安装/打开下载的文件
  Future<void> _installUpdate() async {
    if (_downloadedFilePath == null) return;

    try {
      debugPrint('[AppUpdate] Opening file: $_downloadedFilePath');
      final result = await OpenFile.open(_downloadedFilePath!);
      debugPrint('[AppUpdate] Open result: ${result.message}');

      if (context.mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('[AppUpdate] Failed to open file: $e');
      setState(() {
        _errorMessage = '无法打开文件: $e';
      });
    }
  }

  /// 跳转外部链接（iOS 或下载失败时）
  Future<void> _openExternalUrl() async {
    final uri = Uri.parse(widget.downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !widget.forceUpdate && _state != _UpdateState.downloading,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(77),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _state == _UpdateState.downloaded
                      ? Icons.check_circle_rounded
                      : Icons.system_update_rounded,
                  color: _state == _UpdateState.downloaded
                      ? Colors.green
                      : theme.colorScheme.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),

              // 标题
              Text(
                _getTitle(),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // 版本号
              Text(
                'v${widget.latestVersion}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),

              // 下载进度条
              if (_state == _UpdateState.downloading) ...[
                LinearProgressIndicator(
                  value: _progress,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_progress * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 错误信息
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withAlpha(77),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 强制更新提示
              if (widget.forceUpdate && _state == _UpdateState.idle)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withAlpha(77),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前版本过低，请更新后继续使用',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // 按钮
              _buildButtons(theme),
            ],
          ),
        ),
      ),
    );
  }

  String _getTitle() {
    switch (_state) {
      case _UpdateState.idle:
        return '发现新版本';
      case _UpdateState.downloading:
        return '正在下载';
      case _UpdateState.downloaded:
        return '下载完成';
      case _UpdateState.error:
        return '下载失败';
    }
  }

  Widget _buildButtons(ThemeData theme) {
    switch (_state) {
      case _UpdateState.idle:
        return Row(
          children: [
            // 稍后更新按钮（强制更新时不显示）
            if (!widget.forceUpdate) ...[
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    '稍后更新',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            // 立即更新按钮
            Expanded(
              child: FilledButton(
                onPressed: _needsInAppDownload ? _startDownload : _openExternalUrl,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: theme.colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '立即更新',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        );

      case _UpdateState.downloading:
        return TextButton(
          onPressed: _cancelDownload,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            '取消下载',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

      case _UpdateState.downloaded:
        return FilledButton(
          onPressed: _installUpdate,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            '立即安装',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        );

      case _UpdateState.error:
        return Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _state = _UpdateState.idle),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '重试',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _openExternalUrl,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: theme.colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '浏览器下载',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        );
    }
  }
}
