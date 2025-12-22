/// Phone number + verification code login page.
/// Desktop: Centered single column with glassmorphic card
/// Mobile: Single column with LoginScaffold
library;

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:psygo/widgets/layouts/login_scaffold.dart';
import 'package:psygo/backend/backend.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/pages/login_signup/login_signup.dart' show PolicyBottomSheet;
import 'package:psygo/pages/login_signup/login_flow_mixin.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/window_service.dart';

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  PhoneLoginController createState() => PhoneLoginController();
}

class PhoneLoginController extends State<PhoneLoginPage> with LoginFlowMixin {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();

  @override
  PsygoApiClient get backend => context.read<PsygoApiClient>();

  String? phoneError;
  String? codeError;
  bool loading = false;
  bool agreedToEula = false;
  bool codeSent = false;
  int countdown = 0; // 倒计时秒数
  Timer? _countdownTimer;

  // LoginFlowMixin 实现
  @override
  void setLoginError(String? error) {
    setState(() => codeError = error);
  }

  @override
  void setLoading(bool value) {
    setState(() => loading = value);
  }

  void toggleEulaAgreement() {
    setState(() => agreedToEula = !agreedToEula);
  }

  void requestVerificationCode() async {
    if (!await _ensureEulaAccepted()) {
      return;
    }

    if (phoneController.text.isEmpty) {
      setState(() => phoneError = '请输入您的手机号');
      return;
    }

    if (!phoneController.text.isPhoneNumber) {
      setState(() => phoneError = '请输入正确的手机号');
      return;
    }

    setState(() {
      phoneError = null;
      loading = true;
    });

    try {
      await backend.sendVerificationCode(phoneController.text);

      setState(() {
        codeSent = true;
        loading = false;
        countdown = 60; // 启动60秒倒计时
      });

      // 启动倒计时
      _startCountdown();

      if (mounted) {
        _showSuccessToast('验证码已发送，请注意查收');
      }
    } catch (e) {
      setState(() {
        phoneError = e.toString();
        loading = false;
      });
    }
  }

  // 显示成功提示（与主题风格一致）
  void _showSuccessToast(String message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF00FF9F) : const Color(0xFF00A878);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: isDark
            ? const Color(0xFF00B386)
            : accentColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        elevation: 8,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // 启动倒计时
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown > 0) {
        setState(() {
          countdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  /// 验证码登录（两步流程）
  /// 第一步：verifyPhoneCode → 返回 isNewUser + pendingToken
  /// 第二步：handlePostVerify → 邀请码弹窗（新用户）+ completeLogin + Matrix 登录
  void verifyAndLogin() async {
    if (!await _ensureEulaAccepted()) {
      return;
    }

    if (phoneController.text.isEmpty) {
      setState(() => phoneError = '请输入您的手机号');
      return;
    }

    if (codeController.text.isEmpty) {
      setState(() => codeError = '请输入验证码');
      return;
    }

    setState(() {
      phoneError = null;
      codeError = null;
      loading = true;
    });

    try {
      debugPrint('=== 第一步：验证手机号 + 验证码 ===');
      final verifyResponse = await backend.verifyPhoneCode(
        phoneController.text,
        codeController.text,
      );
      debugPrint('验证结果: phone=${verifyResponse.phone}, isNewUser=${verifyResponse.isNewUser}');

      if (!mounted) return;

      // 使用 mixin 的公共逻辑处理后续流程
      await handlePostVerify(verifyResponse: verifyResponse);
    } catch (e) {
      debugPrint('验证码登录错误: $e');
      setState(() {
        codeError = (e is AutomateBackendException) ? e.message : e.toString();
        loading = false;
      });
    }
  }

  Future<bool> _ensureEulaAccepted() async {
    if (agreedToEula) return true;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A2332);
    final accentColor = isDark ? const Color(0xFF00FF9F) : const Color(0xFF00A878);

    final shouldAccept = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0A1628).withOpacity(0.95),
                    const Color(0xFF0D2233).withOpacity(0.95),
                    const Color(0xFF0F3D3E).withOpacity(0.95),
                  ]
                : [
                    const Color(0xFFF0F4F8).withOpacity(0.98),
                    const Color(0xFFE8EFF5).withOpacity(0.98),
                    const Color(0xFFE0F2F1).withOpacity(0.98),
                  ],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 顶部装饰条
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.2)
                            : Colors.black.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 标题
                  Text(
                    '服务协议与隐私政策',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // 说明文字
                  Text.rich(
                    TextSpan(
                      text: '请您务必审慎阅读、充分理解',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.white.withOpacity(0.7)
                            : const Color(0xFF666666),
                        height: 1.6,
                      ),
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: _ClickableLink(
                            text: '《用户协议》',
                            accentColor: accentColor,
                            onTap: () {
                              Navigator.of(context).pop(false);
                              showEula();
                            },
                          ),
                        ),
                        const TextSpan(text: '和'),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: _ClickableLink(
                            text: '《隐私政策》',
                            accentColor: accentColor,
                            onTap: () {
                              Navigator.of(context).pop(false);
                              showPrivacyPolicy();
                            },
                          ),
                        ),
                        const TextSpan(text: '各条款。点击"同意并继续"代表您已阅读并同意全部内容。'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // 同意按钮（使用渐变样式）
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: isDark
                            ? [
                                const Color(0xFF00B386),
                                const Color(0xFF00D4A1),
                              ]
                            : [
                                accentColor.withOpacity(0.9),
                                accentColor,
                              ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? const Color(0xFF00D3A1) : accentColor)
                              .withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(true),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          child: const Text(
                            '同意并继续',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 不同意按钮
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: isDark
                          ? Colors.white.withOpacity(0.5)
                          : const Color(0xFF999999),
                    ),
                    child: const Text(
                      '不同意',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (shouldAccept == true) {
      setState(() => agreedToEula = true);
      return true;
    }

    return false;
  }

  void showEula() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PolicyBottomSheet(
        title: '用户协议',
        content: _eulaText,
      ),
    );

    if (result == true) {
      setState(() => agreedToEula = true);
    }
  }

  void showPrivacyPolicy() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PolicyBottomSheet(
        title: '隐私政策',
        content: _privacyPolicyText,
      ),
    );

    if (result == true) {
      setState(() => agreedToEula = true);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 统一使用新的响应式设计，自动适配所有屏幕尺寸
    return _buildDesktopLayout(context);
  }

  /// Desktop: Centered single-column layout with dark gradient background and glassmorphism
  Widget _buildDesktopLayout(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Theme detection
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          // Responsive sizing based on available width
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;

          // Responsive breakpoints
          // 超小屏: < 400px (小手机竖屏)
          // 小屏幕: 400-600px (普通手机竖屏)
          // 中等屏幕: 600-900px (平板竖屏/小窗口)
          // 大屏幕: > 900px (平板横屏/桌面)
          final isExtraSmallScreen = screenWidth < 400;
          final isSmallScreen = screenWidth >= 400 && screenWidth < 600;
          final isMediumScreen = screenWidth >= 600 && screenWidth < 900;
          final isLargeScreen = screenWidth >= 900;

          // Logo 尺寸响应式 - 更大 Logo
          final logoSize = isExtraSmallScreen ? 100.0
              : (isSmallScreen ? 110.0
              : (isMediumScreen ? 120.0 : 130.0));
          final logoImageHeight = isExtraSmallScreen ? 55.0
              : (isSmallScreen ? 60.0
              : (isMediumScreen ? 65.0 : 70.0));

          // 标题字体响应式
          final titleFontSize = isExtraSmallScreen ? 28.0
              : (isSmallScreen ? 32.0
              : (isMediumScreen ? 36.0 : 40.0));
          final subtitleFontSize = isExtraSmallScreen ? 10.0
              : (isSmallScreen ? 11.0 : 12.0);

          // 卡片宽度响应式
          final cardMaxWidth = (isExtraSmallScreen || isSmallScreen)
              ? screenWidth * 0.92
              : (isMediumScreen ? 420.0 : 480.0);

          // 间距响应式 - Logo与卡片间距
          final cardSpacingTop = isExtraSmallScreen ? 28.0
              : (isSmallScreen ? 32.0
              : (isMediumScreen ? 40.0 : 48.0));
          final verticalPadding = screenHeight < 700 ? 12.0 : 24.0;
          final horizontalPadding = (isExtraSmallScreen || isSmallScreen) ? 12.0 : 20.0;

          // Theme-based colors
          final bgColors = isDark
              ? [
                  const Color(0xFF0A1628), // Deep blue
                  const Color(0xFF0D2233), // Mid blue
                  const Color(0xFF0F3D3E), // Teal
                ]
              : [
                  const Color(0xFFF0F4F8), // Light blue-gray
                  const Color(0xFFE8EFF5), // Lighter blue
                  const Color(0xFFE0F2F1), // Light cyan
                ];

          final textColor = isDark ? Colors.white : const Color(0xFF1A2332);
          final accentColor = isDark ? const Color(0xFF00FF9F) : const Color(0xFF00A878);

          // PC端使用圆角无边框窗口
          Widget content = Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bgColors,
              ),
              // PC端添加圆角
              borderRadius: PlatformInfos.isDesktop
                  ? BorderRadius.circular(6)
                  : null,
            ),
            child: Stack(
              children: [
                // Background glowing orbs with pulsing animation
                _buildGlowingOrbs(isDark),

                // PC端：顶部拖拽区域
                if (PlatformInfos.isDesktop)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 40,
                    child: WindowDragArea(
                      child: Container(color: Colors.transparent),
                    ),
                  ),

                // PC端：窗口控制按钮（最小化、关闭，不显示最大化）
                if (PlatformInfos.isDesktop)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: WindowControlButtons(
                      showMaximize: false,
                      iconColor: isDark
                          ? Colors.white.withOpacity(0.6)
                          : Colors.black.withOpacity(0.4),
                    ),
                  ),

                // Main content - centered without scrolling
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo with floating animation
                        _AnimatedFloatingLogo(
                          size: logoSize,
                          imageHeight: logoImageHeight,
                          isDark: isDark,
                        ),
                        SizedBox(height: cardSpacingTop),

                        // Glassmorphic login card
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: cardMaxWidth),
                          child: _buildGlassmorphicCard(
                            context,
                            isExtraSmallScreen || isSmallScreen,
                            isDark,
                            textColor,
                            accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );

          // PC端：添加圆角裁剪
          if (PlatformInfos.isDesktop) {
            content = ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: content,
            );
          }

          return content;
        },
      ),
    );
  }

  /// Build animated glowing orbs for background
  Widget _buildGlowingOrbs(bool isDark) {
    // Theme-based glow colors
    final glowColor1 = isDark ? const Color(0xFF00D4FF) : const Color(0xFF4FC3F7);
    final glowColor2 = isDark ? const Color(0xFF00FF9F) : const Color(0xFF81C784);
    final glowColor3 = isDark ? const Color(0xFF0099FF) : const Color(0xFF64B5F6);

    return Stack(
      children: [
        // Top-left glow
        Positioned(
          top: -200,
          left: -200,
          child: _PulsingGlow(
            size: 500,
            color: glowColor1,
            delay: Duration.zero,
            isDark: isDark,
          ),
        ),
        // Bottom-right glow
        Positioned(
          bottom: -200,
          right: -200,
          child: _PulsingGlow(
            size: 500,
            color: glowColor2,
            delay: const Duration(seconds: 2),
            isDark: isDark,
          ),
        ),
        // Center glow
        Positioned.fill(
          child: Center(
            child: _PulsingGlow(
              size: 500,
              color: glowColor3,
              delay: const Duration(seconds: 1),
              isDark: isDark,
            ),
          ),
        ),
      ],
    );
  }

  /// Glassmorphic card container
  Widget _buildGlassmorphicCard(
    BuildContext context,
    bool isSmallScreen,
    bool isDark,
    Color textColor,
    Color accentColor,
  ) {
    final horizontalPadding = isSmallScreen ? 16.0 : 22.0;
    final verticalPadding = isSmallScreen ? 18.0 : 24.0;

    // Theme-based card colors
    final cardBgColor = isDark
        ? Colors.white.withOpacity(0.05)
        : Colors.white.withOpacity(0.4);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.1)
        : Colors.white.withOpacity(0.5);
    final shadowColor = isDark
        ? Colors.black.withOpacity(0.3)
        : Colors.black.withOpacity(0.1);

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: _buildGlassmorphicLoginForm(
              context,
              isSmallScreen,
              isDark,
              textColor,
              accentColor,
            ),
          ),
        ),
      ),
    );
  }

  /// Login form content inside glassmorphic card
  Widget _buildGlassmorphicLoginForm(
    BuildContext context,
    bool isSmallScreen,
    bool isDark,
    Color textColor,
    Color accentColor,
  ) {
    final titleFontSize = isSmallScreen ? 20.0 : 22.0;
    final subtitleFontSize = isSmallScreen ? 11.0 : 12.0;
    final spacingTop = isSmallScreen ? 14.0 : 16.0;
    final spacingBetween = isSmallScreen ? 10.0 : 12.0;

    final subtitleColor = isDark
        ? Colors.white.withOpacity(0.6)
        : const Color(0xFF5A6A7A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title
        Text(
          '登录 / 注册',
          style: TextStyle(
            fontSize: titleFontSize,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        SizedBox(height: spacingTop),

        // Phone input with glow on focus
        // PC端允许在获取验证码后修改手机号，移动端锁定
        _GlowingTextField(
          controller: phoneController,
          hintText: '请输入手机号',
          prefixIcon: Icons.phone_outlined,
          errorText: phoneError,
          readOnly: loading || (codeSent && !PlatformInfos.isDesktop),
          keyboardType: TextInputType.phone,
          textInputAction: codeSent ? TextInputAction.next : TextInputAction.done,
          isDark: isDark,
          accentColor: accentColor,
          onChanged: (value) {
            setState(() => phoneError = null);
          },
          onSubmitted: (_) {
            if (!codeSent && !loading && countdown == 0) {
              requestVerificationCode();
            }
          },
        ),
        SizedBox(height: spacingBetween),

        // Verification code input (shown after code is sent)
        if (codeSent) ...[
          _GlowingTextField(
            controller: codeController,
            hintText: '请输入验证码',
            prefixIcon: Icons.lock_outline,
            errorText: codeError,
            readOnly: loading,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            isDark: isDark,
            accentColor: accentColor,
            onChanged: (value) {
              setState(() => codeError = null);
            },
            onSubmitted: (_) {
              if (!loading) {
                verifyAndLogin();
              }
            },
          ),
          const SizedBox(height: 12),
          // Resend button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: countdown > 0 ? null : requestVerificationCode,
              child: Text(
                countdown > 0 ? '${countdown}秒后重新发送' : '重新发送验证码',
                style: TextStyle(
                  color: countdown > 0
                      ? (isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF9E9E9E))
                      : accentColor,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          SizedBox(height: spacingBetween),
        ],

        // Agreement checkbox
        Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: Checkbox(
                value: agreedToEula,
                onChanged: (loading || codeSent) ? null : (_) => toggleEulaAgreement(),
                fillColor: MaterialStateProperty.resolveWith((states) {
                  if (states.contains(MaterialState.selected)) {
                    return accentColor;
                  }
                  return Colors.transparent;
                }),
                side: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.3)
                      : Colors.black.withOpacity(0.3),
                  width: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 11,
                    color: subtitleColor,
                  ),
                  children: [
                    const TextSpan(text: '我已阅读并同意 '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _ClickableLink(
                        text: '《用户协议》',
                        accentColor: accentColor,
                        onTap: loading ? () {} : showEula,
                        fontSize: 11,
                      ),
                    ),
                    const TextSpan(text: ' 和 '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _ClickableLink(
                        text: '《隐私政策》',
                        accentColor: accentColor,
                        onTap: loading ? () {} : showPrivacyPolicy,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: spacingBetween),

        // Get verification code or Login button
        if (!codeSent)
          _GradientButton(
            onPressed: (loading || countdown > 0) ? null : requestVerificationCode,
            loading: loading,
            text: countdown > 0 ? '${countdown}秒后重试' : '获取验证码',
            isDark: isDark,
            accentColor: accentColor,
          )
        else
          _GradientButton(
            onPressed: loading ? null : verifyAndLogin,
            loading: loading,
            text: '登录 / 注册',
            isDark: isDark,
            accentColor: accentColor,
          ),
      ],
    );
  }

  Widget _buildFeatureItem(BuildContext context, IconData icon, String title, String subtitle) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.onPrimary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: theme.colorScheme.onPrimary,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Mobile: Original LoginScaffold layout
  Widget _buildMobileLayout(BuildContext context) {
    final theme = Theme.of(context);

    return LoginScaffold(
      appBar: null,
      enforceMobileMode: true,
      body: Stack(
        children: [
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: _buildLoginForm(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Shared login form widget
  Widget _buildLoginForm(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDesktop = FluffyThemes.isColumnMode(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!isDesktop) ...[
          Icon(
            Icons.lock_person_outlined,
            size: 80,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
        ],

        // Title
        Text(
          '手机号登录',
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '欢迎回来！请验证您的手机号以继续。',
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 40),

        // Phone Input
        TextField(
          readOnly: loading,
          autocorrect: false,
          autofocus: true,
          controller: phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          style: textTheme.bodyLarge,
          autofillHints: loading ? null : [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: '手机号',
            hintText: '请输入手机号',
            prefixIcon: const Icon(Icons.phone_outlined),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
            ),
            errorText: phoneError,
            suffixIcon: codeSent
                ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                : null,
          ),
        ),
        const SizedBox(height: 16),

        // Code Input
        if (codeSent) ...[
          TextField(
            readOnly: loading,
            autocorrect: false,
            autofocus: true,
            controller: codeController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            style: textTheme.bodyLarge,
            autofillHints: loading ? null : [AutofillHints.oneTimeCode],
            onSubmitted: (_) => verifyAndLogin(),
            decoration: InputDecoration(
              labelText: '验证码',
              hintText: '请输入验证码',
              prefixIcon: const Icon(Icons.security_outlined),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
              ),
              errorText: codeError,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: loading ? null : requestVerificationCode,
              child: const Text('重新发送验证码'),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // EULA
        Row(
          children: [
            Checkbox(
              value: agreedToEula,
              onChanged: loading ? null : (_) => toggleEulaAgreement(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Flexible(
              child: Text.rich(
                TextSpan(
                  style: textTheme.bodyMedium,
                  children: [
                    const TextSpan(text: '我已阅读并同意'),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _ClickableLink(
                        text: '《用户协议》',
                        accentColor: theme.colorScheme.primary,
                        onTap: loading ? () {} : showEula,
                      ),
                    ),
                    const TextSpan(text: '和'),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _ClickableLink(
                        text: '《隐私政策》',
                        accentColor: theme.colorScheme.primary,
                        onTap: loading ? () {} : showPrivacyPolicy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Buttons
        if (!codeSent)
          FilledButton(
            onPressed: loading ? null : requestVerificationCode,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('获取验证码', style: TextStyle(fontSize: 16)),
          ),

        if (codeSent)
          FilledButton(
            onPressed: loading ? null : verifyAndLogin,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: loading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    '登录 / 注册',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
      ],
    );
  }
}

/// Grid pattern painter for background decoration
class _GridPatternPainter extends CustomPainter {
  final Color color;

  _GridPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const spacing = 40.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const String _eulaText = '''
# 用户服务协议

**生效日期：2023年10月1日**

欢迎您使用 Psygo（以下简称"本服务"）。本协议是您与 Psygo 运营方（以下简称"我们"）之间关于您使用本服务所订立的协议。

## 1. 服务内容
本服务是一款基于人工智能技术的自动化助理应用，旨在为您提供智能对话、信息处理及自动化任务执行等服务。我们有权根据业务发展需要，随时调整服务内容或中断服务。

## 2. 账号注册与安全
- 您承诺注册账号时提供的信息真实、准确、完整。
- 您有责任妥善保管您的账号及密码信息。因您保管不善可能导致遭受的盗号或密码失窃，责任由您自行承担。
- 若发现任何非法使用用户账号或存在安全漏洞的情况，请立即通知我们。

## 3. 用户行为规范
您在使用本服务时，必须遵守中华人民共和国相关法律法规及本协议的规定。您不得利用本服务制作、复制、发布、传播如下干扰本服务正常运营，以及侵犯其他用户或第三方合法权益的内容：
- 反对宪法所确定的基本原则的；
- 危害国家安全，泄露国家秘密，颠覆国家政权，破坏国家统一的；
- 散布谣言，扰乱社会秩序，破坏社会稳定的；
- 散布淫秽、色情、赌博、暴力、凶杀、恐怖或者教唆犯罪的；
- 侮辱或者诽谤他人，侵害他人合法权益的；
- 含有法律、行政法规禁止的其他内容的。

## 4. AI 生成内容免责声明
- 本服务提供的回答和内容由人工智能模型生成，仅供参考。
- 我们致力于提高模型输出的准确性，但**不对生成内容的准确性、完整性、可靠性或适用性做任何明示或暗示的保证**。
- 您不应完全依赖 AI 生成的内容进行医疗、法律、金融等专业领域的决策。在做出重大决策前，请咨询相关领域的专业人士。

## 5. 知识产权
- 我们在本服务中提供的内容（包括但不限于软件、技术、程序、网页、文字、图片、图像、音频、视频、图表、版面设计、电子文档等）的知识产权属于我们所有。
- 您在使用本服务过程中产生的内容（如提问、对话记录），您同意授予我们免费的、不可撤销的、非独家的使用许可，用于优化模型和服务体验。

## 6. 隐私保护
我们非常重视您的个人信息保护。我们将按照《隐私政策》收集、存储、使用、披露和保护您的个人信息。请您详细阅读《隐私政策》以了解我们如何保护您的隐私。

## 7. 违约处理
一旦发现您违反本协议的规定，我们有权不经通知单方采取包括但不限于限制、暂停或终止您使用本服务、封禁账号等措施，并追究您的法律责任。

## 8. 其他
- 本协议的效力、解释及纠纷的解决，适用于中华人民共和国法律。
- 若您和我们之间发生任何纠纷或争议，首先应友好协商解决；协商不成的，您同意将纠纷或争议提交至我们所在地有管辖权的人民法院管辖。
''';

const String _privacyPolicyText = '''
# 隐私政策

**生效日期：2023年10月1日**

Psygo（以下简称"我们"）非常重视用户的隐私保护。本隐私政策旨在向您说明我们如何收集、使用、存储和保护您的个人信息。

## 1. 信息收集

我们可能收集以下类型的信息：

### 1.1 您主动提供的信息
- 注册信息：手机号码、昵称、头像等
- 使用服务时提供的内容：对话记录、文件、图片等

### 1.2 自动收集的信息
- 设备信息：设备型号、操作系统版本、唯一设备标识符
- 日志信息：访问时间、功能使用情况、错误日志
- 位置信息：仅在您授权后收集，用于提供位置相关服务

### 1.3 第三方来源的信息
- 通过第三方登录时获取的基本信息（如您选择使用）

## 2. 信息使用

我们收集的信息将用于：
- 提供、维护和改进我们的服务
- 向您发送服务通知和更新
- 检测、预防和解决技术问题和安全问题
- 遵守法律法规的要求
- 优化 AI 模型和提升服务质量（已匿名化处理）

## 3. 信息存储

- 您的信息存储在位于中华人民共和国境内的服务器
- 我们采用行业标准的安全措施保护您的信息
- 信息保存期限为提供服务所必需的期间，或法律法规要求的期间

## 4. 信息共享

我们不会向第三方出售您的个人信息。以下情况除外：
- 获得您的明确同意
- 根据法律法规的要求
- 为保护我们、用户或公众的权益

## 5. 您的权利

您对您的个人信息享有以下权利：
- **访问权**：查看我们收集的关于您的信息
- **更正权**：更正不准确的个人信息
- **删除权**：请求删除您的个人信息
- **注销账号**：您可以随时申请注销账号

## 6. 儿童隐私

我们的服务不面向 14 周岁以下的儿童。如果我们发现收集了儿童的个人信息，将立即删除。

## 7. 隐私政策的变更

我们可能会不时更新本隐私政策。更新后的政策将在本应用内公布，重大变更将通过应用内通知或其他方式告知您。

## 8. 联系我们

如果您对本隐私政策有任何疑问，请通过以下方式联系我们：
- 邮箱：support@creativekoalas.com
''';

// ============================================================================
// Custom Components for Glassmorphic Design
// ============================================================================

/// Pulsing glow orb for background animation
class _PulsingGlow extends StatefulWidget {
  final double size;
  final Color color;
  final Duration delay;
  final bool isDark;

  const _PulsingGlow({
    required this.size,
    required this.color,
    required this.delay,
    required this.isDark,
  });

  @override
  State<_PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<_PulsingGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    // Light mode uses softer opacity
    final minOpacity = widget.isDark ? 0.2 : 0.15;
    final maxOpacity = widget.isDark ? 0.4 : 0.25;

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: minOpacity, end: maxOpacity),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: maxOpacity, end: minOpacity),
        weight: 50,
      ),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.1),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0),
        weight: 50,
      ),
    ]).animate(_controller);

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  widget.color.withOpacity(_opacityAnimation.value),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Floating logo with animation
class _AnimatedFloatingLogo extends StatefulWidget {
  final double size;
  final double imageHeight;
  final bool isDark;

  const _AnimatedFloatingLogo({
    this.size = 120.0,
    this.imageHeight = 65.0,
    this.isDark = true,
  });

  @override
  State<_AnimatedFloatingLogo> createState() => _AnimatedFloatingLogoState();
}

class _AnimatedFloatingLogoState extends State<_AnimatedFloatingLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: Image.asset(
            widget.isDark ? 'assets/logo_dark.png' : 'assets/logo_transparent.png',
            width: widget.size,
            height: widget.size,
          ),
        );
      },
    );
  }
}

/// Glowing text field with focus animation
class _GlowingTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final String? errorText;
  final bool readOnly;
  final TextInputType keyboardType;
  final bool isDark;
  final Color accentColor;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  const _GlowingTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.errorText,
    required this.readOnly,
    required this.keyboardType,
    required this.isDark,
    required this.accentColor,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  @override
  State<_GlowingTextField> createState() => _GlowingTextFieldState();
}

class _GlowingTextFieldState extends State<_GlowingTextField> {
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Theme-based colors
    final textColor = widget.isDark ? Colors.white : const Color(0xFF1A2332);
    final hintColor = widget.isDark
        ? Colors.white.withOpacity(0.4)
        : const Color(0xFF9E9E9E);
    final iconColor = widget.isDark
        ? Colors.white.withOpacity(0.5)
        : const Color(0xFF757575);
    final fillColor = widget.isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.03);
    final borderColor = widget.isDark
        ? Colors.white.withOpacity(0.1)
        : Colors.black.withOpacity(0.15);
    final focusBorderColor = widget.isDark
        ? const Color(0xFF00D4FF)
        : widget.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? focusBorderColor : borderColor,
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: widget.accentColor.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            readOnly: widget.readOnly,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(
                color: hintColor,
              ),
              prefixIcon: Icon(
                widget.prefixIcon,
                color: iconColor,
                size: 18,
              ),
              filled: true,
              fillColor: fillColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.errorText!,
            style: const TextStyle(
              color: Color(0xFFFF6B6B),
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

/// Gradient button with loading state
class _GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String text;
  final bool isDark;
  final Color accentColor;

  const _GradientButton({
    required this.onPressed,
    required this.loading,
    required this.text,
    this.isDark = true,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    // Theme-based gradient colors
    final gradientColors = isDark
        ? [
            const Color(0xFF00B386),
            const Color(0xFF00D4A1),
          ]
        : [
            accentColor.withOpacity(0.9),
            accentColor,
          ];

    final shadowColor = isDark
        ? const Color(0xFF00D3A1).withOpacity(0.3)
        : accentColor.withOpacity(0.25);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                        size: 14,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Clickable link with hover effect
class _ClickableLink extends StatefulWidget {
  final String text;
  final Color accentColor;
  final VoidCallback onTap;
  final double fontSize;

  const _ClickableLink({
    required this.text,
    required this.accentColor,
    required this.onTap,
    this.fontSize = 14,
  });

  @override
  State<_ClickableLink> createState() => _ClickableLinkState();
}

class _ClickableLinkState extends State<_ClickableLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: _isHovered
                    ? widget.accentColor
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          child: Text(
            widget.text,
            style: TextStyle(
              fontSize: widget.fontSize,
              color: _isHovered
                  ? widget.accentColor.withOpacity(0.8)
                  : widget.accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Extensions
// ============================================================================

extension on String {
  static final RegExp _phoneRegex =
      RegExp(r'^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]*$');

  bool get isPhoneNumber => _phoneRegex.hasMatch(this);
}
