import 'dart:async';

import 'package:flutter/material.dart';

import 'package:automate/l10n/l10n.dart';

/// 订单确认页面
/// 按照新 UI 设计重构
class OrderPage extends StatefulWidget {
  final double amount;

  const OrderPage({
    super.key,
    required this.amount,
  });

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  // 选中的支付方式：0 = 微信, 1 = 支付宝, 2 = 银行卡
  int _selectedPayment = 0;

  // 订单号（固定生成一次）
  late final String _orderNo;

  // 倒计时（秒）
  int _countdown = 15 * 60; // 15分钟
  Timer? _timer;

  // 主题绿色
  static const Color _primaryGreen = Color(0xFF4CAF50);
  static const Color _lightGreen = Color(0xFFE8F5E9);

  @override
  void initState() {
    super.initState();
    _orderNo = 'ORD${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
        // 超时处理
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.of(context).orderTimeout),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  String get _countdownText {
    final minutes = _countdown ~/ 60;
    final seconds = _countdown % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _onConfirmPayment() {
    final l10n = L10n.of(context);

    // 显示支付中提示（仅 UI 演示）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _primaryGreen),
            const SizedBox(height: 16),
            Text(l10n.walletProcessing),
          ],
        ),
      ),
    );

    // 模拟支付延迟
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.of(context).pop(); // 关闭 loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.walletPaymentDemo),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              l10n.orderConfirmPayment,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.orderSecureEnvironment,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // 订单信息卡片
                  _buildOrderCard(l10n),
                  const SizedBox(height: 16),
                  // 支付方式选择
                  _buildPaymentMethods(l10n),
                ],
              ),
            ),
          ),
          // 底部支付区域
          _buildBottomSection(l10n),
        ],
      ),
    );
  }

  Widget _buildOrderCard(L10n l10n) {
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
          // 顶部行：充值订单 + 倒计时
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: _primaryGreen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.orderRechargeOrder,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _countdownText,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 订单号
          Text(
            '${l10n.orderNumber}: $_orderNo',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),

          // 支付金额区域
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  l10n.orderPayAmount,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        '¥',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _primaryGreen,
                        ),
                      ),
                    ),
                    Text(
                      widget.amount.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: _primaryGreen,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _lightGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 14,
                        color: _primaryGreen,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${l10n.orderWillGetCredits} ${widget.amount.toStringAsFixed(0)} ${l10n.walletCreditsUnit}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 详情列表
          _buildDetailRow(l10n.orderCreditsAmount2, '${widget.amount.toStringAsFixed(0)} ${l10n.walletCreditsUnit}'),
          const SizedBox(height: 8),
          _buildDetailRow(l10n.orderExchangeRate, '1:1'),
          const SizedBox(height: 8),
          _buildDetailRow(l10n.orderDiscount, '¥0'),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethods(L10n l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: _primaryGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.orderSelectPayment,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 微信支付
          _buildPaymentOption(
            index: 0,
            icon: Icons.wechat,
            iconColor: const Color(0xFF07C160),
            title: l10n.walletWechatPay,
            subtitle: l10n.orderQuickPay,
            isRecommended: true,
            recommendedLabel: l10n.orderRecommended,
          ),
          const SizedBox(height: 12),

          // 支付宝
          _buildPaymentOption(
            index: 1,
            icon: Icons.account_balance_wallet,
            iconColor: const Color(0xFF1677FF),
            title: l10n.walletAlipay,
            subtitle: l10n.orderQuickPay,
            isRecommended: false,
          ),
          const SizedBox(height: 12),

          // 银行卡
          _buildPaymentOption(
            index: 2,
            icon: Icons.credit_card,
            iconColor: const Color(0xFF666666),
            title: l10n.orderBankCard,
            subtitle: l10n.orderDebitCredit,
            isRecommended: false,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption({
    required int index,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isRecommended,
    String? recommendedLabel,
  }) {
    final isSelected = _selectedPayment == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPayment = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _primaryGreen : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 图标
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      if (isRecommended && recommendedLabel != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _lightGreen,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            recommendedLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              color: _primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),

            // 单选按钮
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? _primaryGreen : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _primaryGreen,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection(L10n l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 确认支付按钮
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _onConfirmPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  l10n.orderConfirmPay,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 安全图标行
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSecurityBadge(Icons.lock, l10n.orderSSL),
                const SizedBox(width: 24),
                _buildSecurityBadge(Icons.security, l10n.orderFundSafe),
                const SizedBox(width: 24),
                _buildSecurityBadge(Icons.flash_on, l10n.orderInstant),
              ],
            ),
            const SizedBox(height: 12),

            // 底部提示文字
            Text(
              l10n.orderSecurityHint,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityBadge(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Colors.grey[400],
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}
