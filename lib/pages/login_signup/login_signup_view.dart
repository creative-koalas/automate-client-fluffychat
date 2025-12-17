import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:psygo/widgets/layouts/login_scaffold.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'login_signup.dart';

class LoginSignupView extends StatelessWidget {
  final LoginSignupController controller;

  const LoginSignupView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return LoginScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Main content - centered
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Product Logo
                    Hero(
                      tag: 'product-logo',
                      child: Image.asset(
                        'assets/logo_transparent.png',
                        height: 120,
                      ),
                    ),

                    const SizedBox(height: 48),

                    // EULA Agreement Checkbox
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: controller.agreedToEula,
                            onChanged: controller.loading
                                ? null
                                : (_) => controller.toggleEulaAgreement(),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                style: textTheme.bodyMedium,
                                children: [
                                  const TextSpan(text: '我已阅读并同意'),
                                  WidgetSpan(
                                    child: InkWell(
                                      onTap: controller.loading ? null : controller.showEula,
                                      child: Text(
                                        '《用户协议》',
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const TextSpan(text: '和'),
                                  WidgetSpan(
                                    child: InkWell(
                                      onTap: controller.loading ? null : controller.showPrivacyPolicy,
                                      child: Text(
                                        '《隐私政策》',
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // One-click login button (Mobile only - SDK not supported on desktop)
                    if (PlatformInfos.isMobile) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            minimumSize: const Size.fromHeight(56),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed:
                              controller.loading ? null : controller.oneClickLogin,
                          icon: controller.loading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.phone_android, size: 28),
                          label: Text(
                            controller.loading ? '登录中...' : '本机号码一键登录',
                            style: TextStyle(
                              fontSize: textTheme.titleMedium?.fontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],

                    // SMS verification code login (Desktop/Web only)
                    if (kIsWeb || PlatformInfos.isDesktop) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            minimumSize: const Size.fromHeight(56),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: controller.loading
                              ? null
                              : () => context.go('/login/phone'),
                          icon: controller.loading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.sms_outlined, size: 28),
                          label: Text(
                            controller.loading ? '登录中...' : '短信验证码登录',
                            style: TextStyle(
                              fontSize: textTheme.titleMedium?.fontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],

                    // Error message
                    if (controller.phoneError != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        controller.phoneError!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}
