import 'package:flutter/material.dart';

/// 测试更新弹窗 - 用于预览 UI 效果
/// 使用方法：在设置页面或其他地方调用 AppUpdateTest.showTestDialog(context)
class AppUpdateTest {
  /// 显示场景选择菜单
  static Future<void> showTestDialog(BuildContext context) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;

    await showDialog(
      context: context,
      builder: (context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 400 : 320),
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '选择测试场景',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  _ScenarioButton(
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                    title: '已是最新版本',
                    subtitle: '没有可用更新',
                    onTap: () {
                      Navigator.pop(context);
                      _showNoUpdateSnackBar(context);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ScenarioButton(
                    icon: Icons.system_update_outlined,
                    color: Colors.blue,
                    title: '发现新版本（可选更新）',
                    subtitle: '用户可以选择稍后更新',
                    onTap: () {
                      Navigator.pop(context);
                      _showUpdateDialog(context, forceUpdate: false);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ScenarioButton(
                    icon: Icons.warning_amber_rounded,
                    color: Colors.orange,
                    title: '发现新版本（强制更新）',
                    subtitle: '必须更新才能继续使用',
                    onTap: () {
                      Navigator.pop(context);
                      _showUpdateDialog(context, forceUpdate: true);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ScenarioButton(
                    icon: Icons.error_outline,
                    color: Colors.red,
                    title: '检查更新失败',
                    subtitle: '网络错误或服务器异常',
                    onTap: () {
                      Navigator.pop(context);
                      _showErrorSnackBar(context);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 显示"已是最新版本"提示
  static void _showNoUpdateSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('当前已是最新版本'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 显示"检查更新失败"提示
  static void _showErrorSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('检查更新失败: 网络连接超时'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 显示更新弹窗
  static Future<void> _showUpdateDialog(BuildContext context, {required bool forceUpdate}) async {
    await showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) => _TestUpdateDialog(forceUpdate: forceUpdate),
    );
  }
}

/// 场景选择按钮
class _ScenarioButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ScenarioButton({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestUpdateDialog extends StatefulWidget {
  final bool forceUpdate;

  const _TestUpdateDialog({this.forceUpdate = false});

  @override
  State<_TestUpdateDialog> createState() => _TestUpdateDialogState();
}

enum _UpdateState {
  idle,
  downloading,
  downloaded,
  error,
}

class _TestUpdateDialogState extends State<_TestUpdateDialog> {
  _UpdateState _state = _UpdateState.idle;
  double _progress = 0;
  String? _errorMessage;

  /// 模拟下载
  Future<void> _simulateDownload() async {
    setState(() {
      _state = _UpdateState.downloading;
      _progress = 0;
      _errorMessage = null;
    });

    // 模拟下载进度
    for (var i = 0; i <= 100; i += 5) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() {
        _progress = i / 100;
      });
    }

    setState(() {
      _state = _UpdateState.downloaded;
    });
  }

  void _reset() {
    setState(() {
      _state = _UpdateState.idle;
      _progress = 0;
      _errorMessage = null;
    });
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
                    'v2.5.0',
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
            if (!widget.forceUpdate) ...[
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
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
            Expanded(
              child: FilledButton(
                onPressed: _simulateDownload,
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
          onPressed: _reset,
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
          onPressed: () => Navigator.of(context).pop(),
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
                onPressed: _reset,
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
                onPressed: () => Navigator.of(context).pop(),
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
