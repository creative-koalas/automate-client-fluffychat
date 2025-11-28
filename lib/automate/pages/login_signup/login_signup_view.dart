import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:automate/widgets/layouts/login_scaffold.dart';
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
                    Theme(
                      data: theme.copyWith(
                        checkboxTheme: theme.checkboxTheme.copyWith(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      child: CheckboxListTile(
                        value: controller.agreedToEula,
                        onChanged: controller.loading ? null : (_) => controller.toggleEulaAgreement(),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '我已阅读并同意 ',
                              style: textTheme.bodyMedium,
                            ),
                            InkWell(
                              onTap: controller.loading ? null : controller.showEula,
                              borderRadius: BorderRadius.circular(4),
                              child: Text(
                                '《用户协议》',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // One-click login button
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

          // Bottom - "登录其他账号"
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: TextButton(
                onPressed: controller.loading
                    ? null
                    : () => context.push('/login/phone'),
                child: Text(
                  '登录其他账号',
                  style: textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
