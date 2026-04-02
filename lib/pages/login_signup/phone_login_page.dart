/// Account + password login page.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:psygo/backend/backend.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/pages/login_signup/login_flow_mixin.dart';
import 'package:psygo/utils/localized_exception_extension.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/window_service.dart';
import 'package:psygo/widgets/agreement_webview_page.dart';
import 'package:psygo/widgets/branded_progress_indicator.dart';

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  PhoneLoginController createState() => PhoneLoginController();
}

class PhoneLoginController extends State<PhoneLoginPage> with LoginFlowMixin {
  final TextEditingController accountController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  PsygoApiClient get backend => context.read<PsygoApiClient>();

  String? accountError;
  String? passwordError;
  bool loading = false;
  bool agreedToEula = false;
  bool obscurePassword = true;

  String? _termsUrl;
  String? _privacyUrl;
  bool _loadingAgreements = false;

  @override
  void initState() {
    super.initState();
    _loadAgreements();
  }

  Future<void> _loadAgreements() async {
    if (_loadingAgreements) return;
    setState(() => _loadingAgreements = true);

    try {
      final agreements = await backend.getAgreements();
      if (!mounted) return;

      for (final agreement in agreements) {
        if (agreement.type == 'terms') {
          _termsUrl = agreement.url;
        } else if (agreement.type == 'privacy') {
          _privacyUrl = agreement.url;
        }
      }
      setState(() {});
    } catch (e) {
      debugPrint('Failed to load agreements: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingAgreements = false);
      }
    }
  }

  @override
  void setLoginError(String? error) {
    if (!mounted) return;
    setState(() => passwordError = error);
  }

  @override
  void setLoading(bool value) {
    if (!mounted) return;
    setState(() => loading = value);
  }

  void toggleEulaAgreement() {
    setState(() => agreedToEula = !agreedToEula);
  }

  void togglePasswordVisibility() {
    setState(() => obscurePassword = !obscurePassword);
  }

  Future<void> loginWithPassword() async {
    final l10n = L10n.of(context);
    if (!await _ensureEulaAccepted()) {
      return;
    }

    final account = accountController.text.trim();
    final password = passwordController.text;
    if (account.isEmpty) {
      setState(() => accountError = l10n.pleaseEnterYourUsername);
      return;
    }
    if (password.isEmpty) {
      setState(() => passwordError = l10n.pleaseEnterYourPassword);
      return;
    }

    setState(() {
      accountError = null;
      passwordError = null;
      loading = true;
    });

    try {
      final authResponse = await backend.accountPasswordLogin(
        account,
        password,
      );
      if (!mounted) return;
      await handlePostLogin(authResponse);
    } catch (e) {
      debugPrint('Account password login failed: $e');
      if (!mounted) return;
      setState(() {
        passwordError = e.toLocalizedString(
          context,
          ExceptionContext.phoneLogin,
        );
        loading = false;
      });
    }
  }

  Future<bool> _ensureEulaAccepted() async {
    if (agreedToEula) return true;

    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A2332);
    final accentColor =
        isDark ? const Color(0xFF00FF9F) : const Color(0xFF00A878);

    final shouldAccept = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF0A1628).withValues(alpha: 0.95),
                    const Color(0xFF0D2233).withValues(alpha: 0.95),
                    const Color(0xFF0F3D3E).withValues(alpha: 0.95),
                  ]
                : [
                    const Color(0xFFF0F4F8).withValues(alpha: 0.98),
                    const Color(0xFFE8EFF5).withValues(alpha: 0.98),
                    const Color(0xFFE0F2F1).withValues(alpha: 0.98),
                  ],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
          ),
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
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.authServiceAgreementTitle,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Text.rich(
                    TextSpan(
                      text: l10n.authAgreementReadHint,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.7)
                            : const Color(0xFF666666),
                        height: 1.6,
                      ),
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: _ClickableLink(
                            text: l10n.authTermsOfService,
                            accentColor: accentColor,
                            onTap: () {
                              Navigator.of(context).pop(false);
                              showEula();
                            },
                          ),
                        ),
                        TextSpan(text: l10n.authAgreementAnd),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: _ClickableLink(
                            text: l10n.authPrivacyPolicy,
                            accentColor: accentColor,
                            onTap: () {
                              Navigator.of(context).pop(false);
                              showPrivacyPolicy();
                            },
                          ),
                        ),
                        TextSpan(text: l10n.authAgreementConsentSuffix),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          accentColor.withValues(alpha: 0.9),
                          accentColor,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(true),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          child: Text(
                            l10n.authAgreeAndContinue,
                            style: const TextStyle(
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
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.authDisagree),
                  ),
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

  Future<void> showEula() async {
    final l10n = L10n.of(context);
    if (_termsUrl == null) {
      await _loadAgreements();
      if (_termsUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authAgreementLoadFailedTerms)),
        );
        return;
      }
    }
    await AgreementWebViewPage.open(
      context,
      l10n.authTermsOfService,
      _termsUrl!,
    );
  }

  Future<void> showPrivacyPolicy() async {
    final l10n = L10n.of(context);
    if (_privacyUrl == null) {
      await _loadAgreements();
      if (_privacyUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.authAgreementLoadFailedPrivacy)),
        );
        return;
      }
    }
    await AgreementWebViewPage.open(
      context,
      l10n.authPrivacyPolicy,
      _privacyUrl!,
    );
  }

  @override
  void dispose() {
    accountController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final bgColors = isDark
                ? const [
                    Color(0xFF0A1628),
                    Color(0xFF0D2233),
                    Color(0xFF0F3D3E),
                  ]
                : const [
                    Color(0xFFF0F4F8),
                    Color(0xFFE8EFF5),
                    Color(0xFFE0F2F1),
                  ];
            final textColor = isDark ? Colors.white : const Color(0xFF1A2332);
            final accentColor =
                isDark ? const Color(0xFF00FF9F) : const Color(0xFF00A878);

            Widget content = Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: bgColors,
                ),
                borderRadius:
                    PlatformInfos.isDesktop ? BorderRadius.circular(6) : null,
              ),
              child: Stack(
                children: [
                  _buildGlowingOrbs(isDark),
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
                  if (PlatformInfos.isDesktop)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: WindowControlButtons(
                        showMaximize: false,
                        iconColor: isDark
                            ? Colors.white.withValues(alpha: 0.6)
                            : Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _buildGlassmorphicCard(
                          context,
                          isDark,
                          textColor,
                          accentColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );

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

  Widget _buildGlowingOrbs(bool isDark) {
    final glowColor1 =
        isDark ? const Color(0xFF00D4FF) : const Color(0xFF4FC3F7);
    final glowColor2 =
        isDark ? const Color(0xFF00FF9F) : const Color(0xFF81C784);
    final glowColor3 =
        isDark ? const Color(0xFF0099FF) : const Color(0xFF64B5F6);

    return Stack(
      children: [
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

  Widget _buildGlassmorphicCard(
    BuildContext context,
    bool isDark,
    Color textColor,
    Color accentColor,
  ) {
    final cardBgColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.4);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.white.withValues(alpha: 0.5);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.1);

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
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
            padding: const EdgeInsets.all(24),
            child: _buildLoginForm(context, isDark, textColor, accentColor),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(
    BuildContext context,
    bool isDark,
    Color textColor,
    Color accentColor,
  ) {
    final l10n = L10n.of(context);
    final subtitleColor =
        isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF5A6A7A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Image.asset(
          'assets/logo_transparent.png',
          height: 80,
        ),
        const SizedBox(height: 20),
        Text(
          l10n.login,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '使用账号和密码登录',
          style: TextStyle(
            fontSize: 14,
            color: subtitleColor,
          ),
        ),
        const SizedBox(height: 20),
        _GlowingTextField(
          controller: accountController,
          hintText: l10n.username,
          prefixIcon: Icons.person_outline,
          errorText: accountError,
          readOnly: loading,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          isDark: isDark,
          accentColor: accentColor,
          onChanged: (_) {
            if (accountError != null) {
              setState(() => accountError = null);
            }
          },
        ),
        const SizedBox(height: 12),
        _GlowingTextField(
          controller: passwordController,
          hintText: l10n.password,
          prefixIcon: Icons.lock_outline,
          errorText: passwordError,
          readOnly: loading,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          obscureText: obscurePassword,
          isDark: isDark,
          accentColor: accentColor,
          suffixIcon: IconButton(
            onPressed: loading ? null : togglePasswordVisibility,
            icon: Icon(
              obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
          onSubmitted: (_) => loginWithPassword(),
          onChanged: (_) {
            if (passwordError != null) {
              setState(() => passwordError = null);
            }
          },
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: agreedToEula,
              onChanged: loading ? null : (_) => toggleEulaAgreement(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      color: subtitleColor,
                    ),
                    children: [
                      TextSpan(text: l10n.authAgreementPrefix),
                      WidgetSpan(
                        child: InkWell(
                          onTap: loading ? null : showEula,
                          child: Text(
                            l10n.authTermsOfService,
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      TextSpan(text: l10n.authAgreementAnd),
                      WidgetSpan(
                        child: InkWell(
                          onTap: loading ? null : showPrivacyPolicy,
                          child: Text(
                            l10n.authPrivacyPolicy,
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: loading ? null : loginWithPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: loading
                ? const BrandedProgressIndicator.small(
                    backgroundColor: Colors.transparent,
                  )
                : Text(
                    l10n.login,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ClickableLink extends StatelessWidget {
  final String text;
  final Color accentColor;
  final VoidCallback onTap;

  const _ClickableLink({
    required this.text,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          color: accentColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GlowingTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final String? errorText;
  final bool readOnly;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool isDark;
  final Color accentColor;
  final bool obscureText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  const _GlowingTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    required this.errorText,
    required this.readOnly,
    required this.keyboardType,
    required this.textInputAction,
    required this.isDark,
    required this.accentColor,
    this.obscureText = false,
    this.suffixIcon,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.72);
    final borderColor = errorText != null
        ? Theme.of(context).colorScheme.error
        : Colors.white.withValues(alpha: isDark ? 0.1 : 0.5);
    final textColor = isDark ? Colors.white : const Color(0xFF1A2332);
    final hintColor =
        isDark ? Colors.white.withValues(alpha: 0.45) : const Color(0xFF7C8A96);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.08),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            obscureText: obscureText,
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: hintColor),
              errorText: errorText,
              filled: true,
              fillColor: fillColor,
              prefixIcon: Icon(prefixIcon, color: accentColor),
              suffixIcon: suffixIcon,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: accentColor, width: 1.4),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

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
        final opacity = widget.isDark ? 0.12 : 0.08;
        final scale = 0.92 + (_controller.value * 0.16);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  widget.color.withValues(alpha: opacity),
                  widget.color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
