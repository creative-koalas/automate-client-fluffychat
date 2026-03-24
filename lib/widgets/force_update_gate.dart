import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/api_client.dart';
import '../l10n/l10n.dart';
import '../services/force_update_controller.dart';
import '../utils/custom_http_client.dart';
import '../utils/platform_infos.dart';

class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

enum _InlineUpdateState {
  idle,
  preparing,
  downloading,
  downloaded,
  opening,
  error,
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  _InlineUpdateState _updateState = _InlineUpdateState.idle;
  double _progress = 0;
  String? _errorMessage;
  String? _downloadedFilePath;
  CancelToken? _cancelToken;
  DateTime? _lastProgressUpdate;

  bool get _needsInAppDownload {
    if (PlatformInfos.isWeb) return false;
    if (PlatformInfos.isIOS) return false;
    return true;
  }

  bool get _isBusy {
    return _updateState == _InlineUpdateState.preparing ||
        _updateState == _InlineUpdateState.downloading ||
        _updateState == _InlineUpdateState.opening;
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  String _platformName() {
    if (PlatformInfos.isWeb) return 'web';
    if (PlatformInfos.isAndroid) return 'android';
    if (PlatformInfos.isIOS) return 'ios';
    if (PlatformInfos.isWindows) return 'windows';
    if (PlatformInfos.isMacOS) return 'macos';
    if (PlatformInfos.isLinux) return 'linux';
    return 'unknown';
  }

  String _getFileName(String downloadUrl) {
    final uri = Uri.parse(downloadUrl);
    final pathSegments = uri.pathSegments;
    if (pathSegments.isNotEmpty) {
      final fileName = pathSegments.last;
      if (fileName.contains('.')) {
        return fileName;
      }
    }
    if (PlatformInfos.isWindows) return 'psygo-setup.exe';
    if (PlatformInfos.isMacOS) return 'psygo.dmg';
    if (PlatformInfos.isLinux) return 'psygo.deb';
    if (PlatformInfos.isAndroid) return 'psygo.apk';
    return 'psygo-update';
  }

  bool _isLinkExpired(DioException e) {
    final statusCode = e.response?.statusCode;
    return statusCode == 401 || statusCode == 403 || statusCode == 410;
  }

  Future<String?> _refreshDownloadUrl(
    PsygoApiClient api,
    String currentVersion,
    String platform,
  ) async {
    try {
      final resp = await api.checkAppVersion(
        currentVersion: currentVersion,
        platform: platform,
        publishForceUpdate: false,
      );
      return resp.downloadUrl?.trim();
    } catch (e) {
      final ts = DateTime.now().toIso8601String();
      print('[ForceUpdateGate][$ts] refresh download url failed: $e');
      return null;
    }
  }

  Future<void> _startDownload({
    required String downloadUrl,
    required String currentVersion,
    required String platform,
    required PsygoApiClient api,
    bool isRetry = false,
  }) async {
    final l10n = L10n.of(context);
    setState(() {
      _updateState = _InlineUpdateState.downloading;
      _progress = 0;
      _errorMessage = null;
    });

    final ts = DateTime.now().toIso8601String();
    print(
      '[ForceUpdateGate][$ts] start download: '
      'platform=$platform, retry=$isRetry',
    );

    try {
      final dir = await getTemporaryDirectory();
      final fileName = _getFileName(downloadUrl);
      final filePath = '${dir.path}/$fileName';

      _cancelToken?.cancel();
      final cancelToken = CancelToken();
      _cancelToken = cancelToken;

      final dio = CustomHttpClient.createDio();
      await dio.download(
        downloadUrl,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) {
            return;
          }
          final newProgress = received / total;
          final now = DateTime.now();
          final shouldUpdate = newProgress >= 1.0 ||
              _lastProgressUpdate == null ||
              now.difference(_lastProgressUpdate!).inMilliseconds >= 300;
          if (!shouldUpdate) {
            return;
          }
          _lastProgressUpdate = now;
          setState(() {
            _progress = newProgress >= 1.0 ? 1.0 : newProgress;
          });
        },
      );

      if (!mounted) {
        return;
      }
      final doneTs = DateTime.now().toIso8601String();
      print('[ForceUpdateGate][$doneTs] download success: $filePath');
      setState(() {
        _updateState = _InlineUpdateState.downloaded;
        _progress = 1;
        _downloadedFilePath = filePath;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      if (e is DioException && e.type == DioExceptionType.cancel) {
        final cancelTs = DateTime.now().toIso8601String();
        print('[ForceUpdateGate][$cancelTs] download cancelled by user');
        setState(() {
          _updateState = _InlineUpdateState.idle;
          _progress = 0;
        });
        return;
      }

      if (e is DioException && _isLinkExpired(e) && !isRetry) {
        final refreshTs = DateTime.now().toIso8601String();
        print('[ForceUpdateGate][$refreshTs] download url expired, refreshing');
        final refreshedUrl =
            await _refreshDownloadUrl(api, currentVersion, platform);
        if (refreshedUrl != null && refreshedUrl.isNotEmpty) {
          await _startDownload(
            downloadUrl: refreshedUrl,
            currentVersion: currentVersion,
            platform: platform,
            api: api,
            isRetry: true,
          );
          return;
        }
        setState(() {
          _updateState = _InlineUpdateState.error;
          _errorMessage = l10n.appUpdateDownloadLinkFailed;
        });
        return;
      }

      final errTs = DateTime.now().toIso8601String();
      print('[ForceUpdateGate][$errTs] download failed: $e');
      setState(() {
        _updateState = _InlineUpdateState.error;
        _errorMessage = l10n.appUpdateDownloadFailedRetry;
      });
    }
  }

  Future<void> _openDownloadedFile() async {
    if (_downloadedFilePath == null) {
      return;
    }
    final l10n = L10n.of(context);
    setState(() {
      _updateState = _InlineUpdateState.opening;
      _errorMessage = null;
    });
    try {
      if (PlatformInfos.isAndroid) {
        final canInstall = await _checkInstallPermission();
        if (!canInstall) {
          final granted = await _requestInstallPermission();
          if (!granted) {
            if (!mounted) {
              return;
            }
            setState(() {
              _updateState = _InlineUpdateState.error;
              _errorMessage = l10n.appUpdateInstallPermissionRequired;
            });
            return;
          }
        }
      }

      final result = await OpenFile.open(_downloadedFilePath!);
      if (!mounted) {
        return;
      }
      if (result.type != ResultType.done) {
        setState(() {
          _updateState = _InlineUpdateState.error;
          _errorMessage = l10n.appUpdateOpenFileFailed;
        });
        return;
      }
      setState(() {
        _updateState = _InlineUpdateState.downloaded;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _updateState = _InlineUpdateState.error;
        _errorMessage = l10n.appUpdateOpenFileFailed;
      });
      final ts = DateTime.now().toIso8601String();
      print('[ForceUpdateGate][$ts] open downloaded file failed: $e');
    }
  }

  Future<bool> _checkInstallPermission() async {
    try {
      const channel = MethodChannel('com.psygo.app/install');
      final result =
          await channel.invokeMethod<bool>('canRequestPackageInstalls');
      return result ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _requestInstallPermission() async {
    try {
      const channel = MethodChannel('com.psygo.app/install');
      final result =
          await channel.invokeMethod<bool>('requestInstallPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openExternalUrl(String downloadUrl) async {
    final l10n = L10n.of(context);
    setState(() {
      _updateState = _InlineUpdateState.opening;
      _errorMessage = null;
    });
    try {
      final uri = Uri.parse(downloadUrl);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) {
        return;
      }
      if (!opened) {
        setState(() {
          _updateState = _InlineUpdateState.error;
          _errorMessage = l10n.appUpdateDownloadLinkFailed;
        });
        return;
      }
      setState(() {
        _updateState = _InlineUpdateState.idle;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _updateState = _InlineUpdateState.error;
        _errorMessage = l10n.appUpdateDownloadLinkFailed;
      });
      final ts = DateTime.now().toIso8601String();
      print('[ForceUpdateGate][$ts] open external url failed: $e');
    }
  }

  Future<void> _handleUpdatePressed(ForceUpdateController controller) async {
    if (_isBusy || !controller.isRequired) {
      return;
    }
    final ts = DateTime.now().toIso8601String();
    print(
      '[ForceUpdateGate][$ts] tap update button (inline): '
      'required=${controller.isRequired}, '
      'hasUrl=${controller.status.hasDownloadUrl}, '
      'source=${controller.status.source}',
    );

    setState(() {
      _updateState = _InlineUpdateState.preparing;
      _errorMessage = null;
    });

    final l10n = L10n.of(context);
    final api = context.read<PsygoApiClient>();
    final currentVersion = await PlatformInfos.getVersion();
    final platform = _platformName();

    AppVersionResponse? response;
    try {
      response = await api.checkAppVersion(
        currentVersion: currentVersion,
        platform: platform,
        publishForceUpdate: false,
      );
      final respTs = DateTime.now().toIso8601String();
      print(
        '[ForceUpdateGate][$respTs] version check ok: '
        'force=${response.forceUpdate}, '
        'hasUrl=${(response.downloadUrl ?? '').trim().isNotEmpty}, '
        'latest=${response.latestVersion}',
      );
    } catch (e) {
      final errTs = DateTime.now().toIso8601String();
      print('[ForceUpdateGate][$errTs] version check failed, fallback snapshot: $e');
    }

    if (!mounted) {
      return;
    }
    final responseUrl = response?.downloadUrl?.trim() ?? '';
    final snapshotUrl = controller.status.downloadUrl?.trim() ?? '';
    final downloadUrl = responseUrl.isNotEmpty ? responseUrl : snapshotUrl;

    if (downloadUrl.isEmpty) {
      setState(() {
        _updateState = _InlineUpdateState.error;
        _errorMessage = response == null
            ? l10n.appUpdateCheckFailed
            : l10n.appUpdateDownloadLinkFailed;
      });
      return;
    }

    if (_needsInAppDownload) {
      await _startDownload(
        downloadUrl: downloadUrl,
        currentVersion: currentVersion,
        platform: platform,
        api: api,
      );
      return;
    }

    await _openExternalUrl(downloadUrl);
  }

  Widget _buildInlineUpdateStatus(ThemeData theme) {
    final l10n = L10n.of(context);
    if (_updateState == _InlineUpdateState.downloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 8,
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _progress.clamp(0.0, 1.0),
                child: Container(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.appUpdateTitleDownloading} ${(_progress * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    if (_updateState == _InlineUpdateState.downloaded) {
      return Text(
        l10n.appUpdateTitleDownloaded,
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.green,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    if (_errorMessage != null && _errorMessage!.trim().isNotEmpty) {
      return Text(
        _errorMessage!,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildPrimaryButton(ForceUpdateController controller) {
    final l10n = L10n.of(context);
    if (_updateState == _InlineUpdateState.downloaded) {
      return FilledButton(
        onPressed: _openDownloadedFile,
        child: Text(l10n.appUpdateInstallNow),
      );
    }
    if (_updateState == _InlineUpdateState.downloading) {
      return FilledButton(
        onPressed: () => _cancelToken?.cancel(),
        child: Text(l10n.appUpdateCancelDownload),
      );
    }
    return FilledButton(
      onPressed: _isBusy ? null : () => _handleUpdatePressed(controller),
      child: _isBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
              ),
            )
          : Text(l10n.appUpdateNow),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ForceUpdateController>();
    if (!controller.hasLoaded) {
      return Stack(
        children: [
          IgnorePointer(
            ignoring: true,
            child: widget.child,
          ),
          const Positioned.fill(
            child: Material(
              color: Colors.black12,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ],
      );
    }
    if (!controller.isRequired) {
      return widget.child;
    }

    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final snapshot = controller.status;
    final latestVersion = snapshot.latestVersion.trim();
    final minVersion = snapshot.minVersion.trim();
    final message = snapshot.message.trim();
    final hasDownloadUrl = snapshot.hasDownloadUrl;

    return Stack(
      children: [
        IgnorePointer(
          ignoring: true,
          child: widget.child,
        ),
        Positioned.fill(
          child: Material(
            color: isDark ? const Color(0xFF0B131A) : const Color(0xFFF4EFE6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF0B131A),
                          Color(0xFF1A2733),
                          Color(0xFF123645),
                        ]
                      : const [
                          Color(0xFFF7F3EA),
                          Color(0xFFEDE7DC),
                          Color(0xFFE1ECE8),
                        ],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : const Color(0xFF163A4D).withValues(alpha: 0.10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFFFFB37A).withValues(alpha: 0.16)
                                : const Color(0xFFE08F47).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.system_update_alt_rounded,
                            size: 34,
                            color: isDark
                                ? const Color(0xFFFFCFA7)
                                : const Color(0xFFB8682B),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l10n.authNeedUpdateTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF18242D),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.authNeedUpdateMessage,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.45,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.78)
                                : const Color(0xFF56626B),
                          ),
                        ),
                        if (latestVersion.isNotEmpty || minVersion.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : const Color(0xFFF8F5EE),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (latestVersion.isNotEmpty)
                                  Text(
                                    '${l10n.version}: $latestVersion',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.92)
                                          : const Color(0xFF1F2F39),
                                    ),
                                  ),
                                if (minVersion.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Min: $minVersion',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.72)
                                          : const Color(0xFF5A6A74),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (message.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.72)
                                  : const Color(0xFF5A6A74),
                            ),
                          ),
                        ],
                        if (!hasDownloadUrl) ...[
                          const SizedBox(height: 12),
                          Text(
                            l10n.appUpdateDownloadLinkFailed,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _buildInlineUpdateStatus(theme),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: _buildPrimaryButton(controller),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: controller.isRefreshing || _isBusy
                                ? null
                                : () => controller.refreshStatus(),
                            child: controller.isRefreshing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Text(l10n.authCheckAgain),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
