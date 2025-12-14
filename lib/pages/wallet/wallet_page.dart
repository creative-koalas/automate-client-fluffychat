import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:psygo/l10n/l10n.dart';

import 'order_page.dart';

/// 钱包充值页面
/// 按照新 UI 设计重构
/// Credit 与人民币 1:1 兑换（1元 = 1分）
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  // 预设金额选项
  final List<int> _presetAmounts = [10, 50, 100, 200, 500];

  // 选中的预设金额索引
  int _selectedPresetIndex = 1; // 默认选中 50

  // 自定义金额
  int _customAmount = 50;

  // 模拟余额（分）
  final int _balanceCredits = 1234;

  // 主题绿色
  static const Color _primaryGreen = Color(0xFF4CAF50);
  static const Color _lightGreen = Color(0xFFE8F5E9);

  @override
  void initState() {
    super.initState();
    _customAmount = _presetAmounts[_selectedPresetIndex];
  }

  void _onPresetTap(int index) {
    setState(() {
      _selectedPresetIndex = index;
      _customAmount = _presetAmounts[index];
    });
  }

  void _onAmountIncrease() {
    setState(() {
      _customAmount += 10;
      _selectedPresetIndex = -1; // 取消预设选中
    });
  }

  void _onAmountDecrease() {
    if (_customAmount > 10) {
      setState(() {
        _customAmount -= 10;
        _selectedPresetIndex = -1; // 取消预设选中
      });
    }
  }

  void _onRecharge() {
    if (_customAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).walletEnterValidAmount),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 跳转到订单页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OrderPage(amount: _customAmount.toDouble()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        title: Text(
          l10n.walletTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // 余额卡片
            _buildBalanceCard(l10n),
            const SizedBox(height: 20),

            // 充值区域
            _buildRechargeCard(l10n),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(L10n l10n) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final lightPrimaryColor = theme.colorScheme.primaryContainer;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: lightPrimaryColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部行：当前余额 + 实时更新
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.walletBalance,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  // TODO: 实时更新余额
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh,
                      size: 14,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.walletRefresh,
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 余额数字
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _balanceCredits.toString().replaceAllMapped(
                      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                      (Match m) => '${m[1]},',
                    ),
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                l10n.walletCreditsUnit,
                style: TextStyle(
                  fontSize: 18,
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 人民币换算
          Text(
            '${l10n.walletEquivalent} ¥${(_balanceCredits / 100).toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 12),

          // 提示信息
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.walletExchangeRate,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRechargeCard(L10n l10n) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final lightPrimaryColor = theme.colorScheme.primaryContainer;
    final surfaceColor = theme.colorScheme.surface;
    final onSurfaceColor = theme.colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: lightPrimaryColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt,
                      size: 16,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.walletCustomRecharge,
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.walletFlexibleRecharge,
            style: TextStyle(
              fontSize: 13,
              color: onSurfaceColor.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 20),

          // 快捷金额标签
          Text(
            l10n.walletQuickAmount,
            style: TextStyle(
              fontSize: 13,
              color: onSurfaceColor.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 10),

          // 快捷金额按钮
          Row(
            children: List.generate(_presetAmounts.length, (index) {
              final amount = _presetAmounts[index];
              final isSelected = _selectedPresetIndex == index;

              return Expanded(
                child: GestureDetector(
                  onTap: () => _onPresetTap(index),
                  child: Container(
                    margin: EdgeInsets.only(
                      right: index < _presetAmounts.length - 1 ? 8 : 0,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? primaryColor : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? primaryColor : theme.colorScheme.outline.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '¥$amount',
                        style: TextStyle(
                          color: isSelected ? theme.colorScheme.onPrimary : onSurfaceColor.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),

          // 自定义金额标签
          Text(
            l10n.walletCustomAmount,
            style: TextStyle(
              fontSize: 13,
              color: onSurfaceColor.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 14),

          // 自定义金额输入（带 +/- 按钮）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // 减少按钮
                _buildAmountButton(
                  icon: Icons.remove,
                  onTap: _onAmountDecrease,
                  enabled: _customAmount > 10,
                ),
                // 金额显示
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '¥',
                          style: TextStyle(
                            fontSize: 16,
                            color: onSurfaceColor.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _customAmount.toString(),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: onSurfaceColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 增加按钮
                _buildAmountButton(
                  icon: Icons.add,
                  onTap: _onAmountIncrease,
                  enabled: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 将获得积分提示
          Center(
            child: Text(
              '${l10n.walletWillGet} $_customAmount${l10n.walletCreditsUnit}',
              style: TextStyle(
                fontSize: 13,
                color: primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // 充值按钮
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _onRecharge,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: theme.colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
              child: Text(
                '${l10n.walletRechargeNow} ¥$_customAmount',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? theme.colorScheme.onSurface.withOpacity(0.7)
              : theme.colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
    );
  }
}
