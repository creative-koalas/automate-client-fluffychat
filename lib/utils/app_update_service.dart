import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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

  // 后台定时检查
  static Timer? _backgroundTimer;
  static bool _isDialogShowing = false;
  static bool _hasSuccessfulCheck = false;  // 是否成功检查过一次
  static const Duration _checkInterval = Duration(minutes: 5);
  static const Duration _retryInterval = Duration(seconds: 30);  // 首次失败后的重试间隔
  static const Duration _resumeDebounce = Duration(seconds: 3);  // 恢复检查的防抖时间

  // 保存引用以便重试
  static PsygoApiClient? _apiClient_;
  static BuildContext Function()? _getContext;

  // 网络监听
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static bool _wasOffline = false;  // 上次是否处于离线状态
  static DateTime? _lastCheckTime;  // 上次检查时间，用于防抖

  AppUpdateService(this._apiClient);

  /// 启动后台定时检查
  static void startBackgroundCheck(PsygoApiClient apiClient, BuildContext Function() getContext) {
    // 避免重复启动
    if (_backgroundTimer != null) return;

    _apiClient_ = apiClient;
    _getContext = getContext;

    debugPrint('[AppUpdate] Starting background check every $_checkInterval');

    // 1. 定时检查（每5分钟）
    _backgroundTimer = Timer.periodic(_checkInterval, (_) async {
      await _doBackgroundCheck();
    });

    // 2. 网络恢复时检查
    _startNetworkListener();
  }

  /// 启动网络状态监听
  static void _startNetworkListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isOffline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);

      if (_wasOffline && !isOffline) {
        // 从离线恢复到在线
        debugPrint('[AppUpdate] Network restored, triggering check');
        _triggerCheckWithDebounce();
      }

      _wasOffline = isOffline;
    });

    // 初始化离线状态
    Connectivity().checkConnectivity().then((results) {
      _wasOffline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      debugPrint('[AppUpdate] Initial network state: ${_wasOffline ? "offline" : "online"}');
    });
  }

  /// 应用从后台恢复时调用
  static void onAppResumed() {
    debugPrint('[AppUpdate] App resumed, triggering check');
    _triggerCheckWithDebounce();
  }

  /// 带防抖的检查触发
  static void _triggerCheckWithDebounce() {
    final now = DateTime.now();
    if (_lastCheckTime != null && now.difference(_lastCheckTime!) < _resumeDebounce) {
      debugPrint('[AppUpdate] Check debounced, skipping');
      return;
    }
    _lastCheckTime = now;
    _doBackgroundCheck();
  }

  /// 执行后台检查
  static Future<void> _doBackgroundCheck() async {
    // 如果已经有弹窗在显示，跳过本次检查
    if (_isDialogShowing) {
      debugPrint('[AppUpdate] Dialog is showing, skip background check');
      return;
    }

    if (_apiClient_ == null || _getContext == null) return;

    final context = _getContext!();
    if (!context.mounted) return;

    final service = AppUpdateService(_apiClient_!);
    await service._silentCheck(context);
  }

  /// 首次检查失败时调用，启动短间隔重试
  static void _scheduleRetry() {
    if (_hasSuccessfulCheck) return;  // 已经成功检查过，不需要重试

    debugPrint('[AppUpdate] Scheduling retry in $_retryInterval');

    Future.delayed(_retryInterval, () async {
      if (_hasSuccessfulCheck) return;  // 再次检查，避免重复
      await _doBackgroundCheck();
    });
  }

  /// 标记首次检查成功
  static void _markCheckSuccess() {
    _hasSuccessfulCheck = true;
  }

  /// 停止后台定时检查
  static void stopBackgroundCheck() {
    debugPrint('[AppUpdate] Stopping background check');
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _hasSuccessfulCheck = false;
    _wasOffline = false;
    _lastCheckTime = null;
    _apiClient_ = null;
    _getContext = null;
  }

  /// 静默检查更新（后台调用，只在有更新时才弹窗）
  Future<void> _silentCheck(BuildContext context) async {
    try {
      final currentVersion = await PlatformInfos.getVersion();
      final platform = _getPlatformName();

      debugPrint('[AppUpdate] Background check: version=$currentVersion, platform=$platform');

      final response = await _apiClient.checkAppVersion(
        currentVersion: currentVersion,
        platform: platform,
      );

      // 检查成功，标记已成功检查
      _markCheckSuccess();

      if (!response.hasUpdate) {
        debugPrint('[AppUpdate] Background check: no update available');
        return;
      }

      if (!context.mounted) return;

      debugPrint('[AppUpdate] Background check: update available v${response.latestVersion}');

      // 标记弹窗正在显示
      _isDialogShowing = true;

      // 显示更新弹窗
      await showDialog<bool>(
        context: context,
        barrierDismissible: !response.forceUpdate,
        builder: (context) => _UpdateDialog(
          latestVersion: response.latestVersion,
          forceUpdate: response.forceUpdate,
          downloadUrl: response.downloadUrl!,
        ),
      );

      _isDialogShowing = false;
    } catch (e) {
      debugPrint('[AppUpdate] Background check failed: $e');
      // 静默检查失败，如果从未成功检查过，安排重试
      // 但如果是 404/500 等服务器错误，不重试（API 不存在或服务器问题）
      if (!_isServerError(e)) {
        _scheduleRetry();
      }
    }
  }

  /// 判断是否为服务器错误（不需要重试）
  static bool _isServerError(dynamic e) {
    if (e is DioException) {
      final statusCode = e.response?.statusCode;
      // 404 = API 不存在, 500/502/503 = 服务器错误
      if (statusCode != null && (statusCode == 404 || statusCode >= 500)) {
        debugPrint('[AppUpdate] Server error ($statusCode), skip retry');
        return true;
      }
    }
    return false;
  }

  /// 检查更新并显示弹窗
  /// 返回 true 表示用户可以继续使用，false 表示被强制更新阻止
  /// [showNoUpdateHint] 为 true 时，如果没有更新也会显示提示
  Future<bool> checkAndPrompt(BuildContext context, {bool showNoUpdateHint = false}) async {
    try {
      final currentVersion = await PlatformInfos.getVersion();
      final platform = _getPlatformName();

      debugPrint('[AppUpdate] Checking update: version=$currentVersion, platform=$platform');

      final response = await _apiClient.checkAppVersion(
        currentVersion: currentVersion,
        platform: platform,
      );

      // 检查成功，标记已成功检查
      _markCheckSuccess();

      debugPrint('[AppUpdate] Response: hasUpdate=${response.hasUpdate}, forceUpdate=${response.forceUpdate}');

      if (!response.hasUpdate) {
        // 已是最新版本
        if (showNoUpdateHint && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前已是最新版本')),
          );
        }
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
      // 首次检查失败，安排重试（服务器错误除外）
      if (!_isServerError(e)) {
        _scheduleRetry();
      }
      // 检查失败时不阻止用户使用，但如果是手动检查则显示错误
      if (showNoUpdateHint && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('检查更新失败: $e')),
        );
      }
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
    final screenWidth = MediaQuery.of(context).size.width;
    // PC端（宽度 > 600）使用更大的尺寸
    final isDesktop = screenWidth > 600;

    final dialogWidth = isDesktop ? 480.0 : 340.0;
    final padding = isDesktop ? 36.0 : 24.0;
    final iconSize = isDesktop ? 88.0 : 64.0;
    final iconInnerSize = isDesktop ? 44.0 : 32.0;
    final titleStyle = isDesktop ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge;
    final versionStyle = isDesktop ? theme.textTheme.titleLarge : theme.textTheme.titleMedium;
    final progressHeight = isDesktop ? 8.0 : 6.0;
    final buttonPadding = isDesktop ? 16.0 : 14.0;

    return PopScope(
      canPop: !widget.forceUpdate && _state != _UpdateState.downloading,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogWidth),
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 图标
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withAlpha(77),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _state == _UpdateState.downloaded
                          ? Icons.check_circle_rounded
                          : isDesktop
                              ? Icons.downloading_rounded  // PC端用下载图标
                              : Icons.system_update_rounded,  // 移动端用系统更新图标
                      color: _state == _UpdateState.downloaded
                          ? Colors.green
                          : theme.colorScheme.primary,
                      size: iconInnerSize,
                    ),
                  ),
                  SizedBox(height: isDesktop ? 28.0 : 20.0),

                  // 标题
                  Text(
                    _getTitle(),
                    style: titleStyle?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 版本号
                  Text(
                    'v${widget.latestVersion}',
                    style: versionStyle?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: isDesktop ? 24.0 : 16.0),

                  // 下载进度条
                  if (_state == _UpdateState.downloading) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: progressHeight,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(_progress * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: isDesktop ? 24.0 : 16.0),
                  ],

                  // 错误信息
                  if (_errorMessage != null) ...[
                    Container(
                      padding: EdgeInsets.all(isDesktop ? 16.0 : 12.0),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withAlpha(77),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                            size: isDesktop ? 24.0 : 20.0,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isDesktop ? 24.0 : 16.0),
                  ],

                  // 强制更新提示
                  if (widget.forceUpdate && _state == _UpdateState.idle)
                    Container(
                      padding: EdgeInsets.all(isDesktop ? 16.0 : 12.0),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withAlpha(77),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: theme.colorScheme.error,
                            size: isDesktop ? 24.0 : 20.0,
                          ),
                          const SizedBox(width: 10),
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

                  SizedBox(height: isDesktop ? 32.0 : 24.0),

                  // 按钮
                  _buildButtons(theme, buttonPadding),
                ],
              ),
            ),
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

  Widget _buildButtons(ThemeData theme, double buttonPadding) {
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
                    padding: EdgeInsets.symmetric(vertical: buttonPadding),
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
                  padding: EdgeInsets.symmetric(vertical: buttonPadding),
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
            padding: EdgeInsets.symmetric(vertical: buttonPadding, horizontal: 32),
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
            padding: EdgeInsets.symmetric(vertical: buttonPadding, horizontal: 32),
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
                  padding: EdgeInsets.symmetric(vertical: buttonPadding),
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
                  padding: EdgeInsets.symmetric(vertical: buttonPadding),
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
