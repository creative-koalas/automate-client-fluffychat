import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

import '../../models/plugin.dart';
import '../../repositories/plugin_repository.dart';
import '../../utils/retry_helper.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton_card.dart';
import '../../widgets/plugin_card.dart';
import '../../widgets/training_detail_sheet.dart';

/// 培训市场 Tab
/// 展示可安装的插件（技能培训）
class TrainingTab extends StatefulWidget {
  const TrainingTab({super.key});

  @override
  State<TrainingTab> createState() => _TrainingTabState();
}

class _TrainingTabState extends State<TrainingTab>
    with AutomaticKeepAliveClientMixin {
  final PluginRepository _repository = PluginRepository();

  List<Plugin> _plugins = [];
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadPlugins();
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  Future<void> _loadPlugins() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final plugins = await RetryHelper.withRetry(
        operation: () => _repository.getPluginsWithStats(),
        maxRetries: 2,
        retryDelayMs: 3000,
        onRetry: (attempt, error) {
          debugPrint('Retrying plugins load, attempt $attempt');
        },
      );
      if (mounted) {
        setState(() {
          _plugins = plugins;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onPluginTap(Plugin plugin) async {
    // 打开培训详情 Sheet
    // 注意：不要用 GestureDetector 包装，否则会吞掉 barrier 的点击事件
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: true, // 点击外部关闭
      enableDrag: true, // 支持拖动关闭
      builder: (context) => TrainingDetailSheet(
        plugin: plugin,
        onInstalled: () {
          // 安装成功后刷新列表
          _loadPlugins();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return RefreshIndicator(
      onRefresh: _loadPlugins,
      color: theme.colorScheme.primary,
      child: _buildBody(context, theme, l10n),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme, L10n l10n) {
    // 加载状态
    if (_isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: SkeletonCard(height: 88),
        ),
      );
    }

    // 错误状态 - 包裹在可滚动组件中以支持下拉刷新
    if (_error != null && _plugins.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.errorLoadingData,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _loadPlugins,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.tryAgain),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 空状态 - 包裹在可滚动组件中以支持下拉刷新
    if (_plugins.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: EmptyState(
            icon: Icons.school_outlined,
            title: l10n.noTrainingAvailable,
            subtitle: l10n.noTrainingHint,
          ),
        ),
      );
    }

    // 插件列表
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 96, // 为底部导航栏留出空间
      ),
      itemCount: _plugins.length,
      itemBuilder: (context, index) {
        final plugin = _plugins[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PluginCard(
            plugin: plugin,
            onTap: () => _onPluginTap(plugin),
          ),
        );
      },
    );
  }
}
