import 'package:flutter/material.dart';
import 'package:psygo/l10n/l10n.dart';

/// 充值成功页面
/// 采用翡翠绿主色调，包含勾选动画和数字递增动画
class PaymentSuccessPage extends StatefulWidget {
  final double amount;
  final int credits;

  const PaymentSuccessPage({
    super.key,
    required this.amount,
    required this.credits,
  });

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage>
    with TickerProviderStateMixin {
  // 翡翠绿主色调
  static const Color _emeraldGreen = Color(0xFF10B981);
  static const Color _emeraldLight = Color(0xFFD1FAE5);

  // 动画控制器
  late AnimationController _checkController;
  late AnimationController _numberController;
  late AnimationController _pulseController;

  // 动画
  late Animation<double> _checkAnimation;
  late Animation<double> _numberAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // 勾选动画 (SVG路径绘制效果)
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _checkAnimation = CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeOutBack,
    );

    // 数字递增动画
    _numberController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _numberAnimation = CurvedAnimation(
      parent: _numberController,
      curve: Curves.easeOutCubic,
    );

    // 脉冲光晕动画
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOut,
    );

    // 启动动画序列
    _startAnimations();
  }

  void _startAnimations() async {
    // 先启动脉冲动画
    _pulseController.forward();

    // 延迟后启动勾选动画
    await Future.delayed(const Duration(milliseconds: 200));
    _checkController.forward();

    // 延迟后启动数字动画
    await Future.delayed(const Duration(milliseconds: 400));
    _numberController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _numberController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildSuccessCard(l10n),
                ),
              ),
            ),
            // 底部提示
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Text(
                '积分可用于 AI 对话消耗',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[400],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard(L10n l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _emeraldLight,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _emeraldGreen.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 勾选图标 + 脉冲动画
          _buildCheckIcon(),
          const SizedBox(height: 20),

          // 充值成功文字
          const Text(
            '充值成功',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: _emeraldGreen,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 32),

          // 分割线
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.grey[200]!,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // 积分数字
          _buildCreditsNumber(l10n),
          const SizedBox(height: 12),

          // 支付金额信息
          Text(
            '支付 ¥${widget.amount.toStringAsFixed(0)} · 已到账',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 32),

          // 完成按钮
          _buildDoneButton(),
        ],
      ),
    );
  }

  Widget _buildCheckIcon() {
    return AnimatedBuilder(
      animation: Listenable.merge([_checkAnimation, _pulseAnimation]),
      builder: (context, child) {
        return SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 外层脉冲光晕
              if (_pulseAnimation.value > 0)
                Transform.scale(
                  scale: 1 + _pulseAnimation.value * 0.3,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _emeraldGreen.withValues(
                        alpha: 0.15 * (1 - _pulseAnimation.value),
                      ),
                    ),
                  ),
                ),

              // 中间光晕
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _emeraldGreen.withValues(alpha: 0.1),
                ),
              ),

              // 主圆形背景
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _emeraldGreen,
                  boxShadow: [
                    BoxShadow(
                      color: _emeraldGreen.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),

              // 勾选图标 (带绘制动画)
              Transform.scale(
                scale: _checkAnimation.value,
                child: CustomPaint(
                  size: const Size(32, 32),
                  painter: _CheckPainter(
                    progress: _checkAnimation.value,
                    color: Colors.white,
                    strokeWidth: 3.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCreditsNumber(L10n l10n) {
    return AnimatedBuilder(
      animation: _numberAnimation,
      builder: (context, child) {
        final displayCredits = (widget.credits * _numberAnimation.value).round();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // 积分数字 (使用 DM Sans 风格)
            Text(
              '$displayCredits',
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
                letterSpacing: -2,
                height: 1,
                fontFamily: 'sans-serif',
              ),
            ),
            const SizedBox(width: 8),
            // 单位
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l10n.walletCreditsUnit,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDoneButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).pop(true),
        style: ElevatedButton.styleFrom(
          backgroundColor: _emeraldGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: _emeraldGreen.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Text(
          '完成',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// 勾选图标绘制器 (模拟 SVG 路径动画)
class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _CheckPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();

    // 勾选路径起点和终点
    final startX = size.width * 0.2;
    final startY = size.height * 0.5;
    final midX = size.width * 0.4;
    final midY = size.height * 0.7;
    final endX = size.width * 0.8;
    final endY = size.height * 0.3;

    // 根据 progress 绘制路径
    if (progress > 0) {
      path.moveTo(startX, startY);

      if (progress <= 0.5) {
        // 绘制第一段 (起点到拐点)
        final t = progress * 2;
        final currentX = startX + (midX - startX) * t;
        final currentY = startY + (midY - startY) * t;
        path.lineTo(currentX, currentY);
      } else {
        // 绘制完整第一段
        path.lineTo(midX, midY);

        // 绘制第二段 (拐点到终点)
        final t = (progress - 0.5) * 2;
        final currentX = midX + (endX - midX) * t;
        final currentY = midY + (endY - midY) * t;
        path.lineTo(currentX, currentY);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
