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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
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
            // 余额卡片
            _buildBalanceCard(l10n),
            const SizedBox(height: 16),

            // 充值区域
            _buildRechargeCard(l10n),
            const SizedBox(height: 16),

            // 为什么选择我们
            _buildWhyChooseUs(l10n),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(L10n l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _lightGreen,
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
                    decoration: const BoxDecoration(
                      color: _primaryGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.walletBalance,
                    style: TextStyle(
                      color: Colors.grey[700],
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
                      color: _primaryGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.walletRefresh,
                      style: const TextStyle(
                        color: _primaryGreen,
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
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                l10n.walletCreditsUnit,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[700],
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
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),

          // 提示信息
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.walletExchangeRate,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                  color: _lightGreen,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.bolt,
                      size: 16,
                      color: _primaryGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.walletCustomRecharge,
                      style: const TextStyle(
                        color: _primaryGreen,
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
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 20),

          // 快捷金额标签
          Text(
            l10n.walletQuickAmount,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
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
                      color: isSelected ? _primaryGreen : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? _primaryGreen : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '¥$amount',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
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
          const SizedBox(height: 20),

          // 自定义金额标签
          Text(
            l10n.walletCustomAmount,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),

          // 自定义金额输入（带 +/- 按钮）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
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
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _customAmount.toString(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
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
          const SizedBox(height: 8),

          // 将获得积分提示
          Center(
            child: Text(
              '${l10n.walletWillGet} $_customAmount${l10n.walletCreditsUnit}',
              style: TextStyle(
                fontSize: 13,
                color: _primaryGreen,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 充值按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _onRecharge,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryGreen,
                foregroundColor: Colors.white,
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
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? Colors.grey[700] : Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildWhyChooseUs(L10n l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.walletWhyChooseUs,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.auto_awesome,
                  title: l10n.walletFeature1Title,
                  subtitle: l10n.walletFeature1Desc,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.flash_on,
                  title: l10n.walletFeature2Title,
                  subtitle: l10n.walletFeature2Desc,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.security,
                  title: l10n.walletFeature3Title,
                  subtitle: l10n.walletFeature3Desc,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.receipt_long,
                  title: l10n.walletFeature4Title,
                  subtitle: l10n.walletFeature4Desc,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _lightGreen,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: _primaryGreen,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
