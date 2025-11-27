import 'package:flutter/material.dart';
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
        title: Text(
          '登录 / 注册',
          style: textTheme.titleLarge,
        ),
        centerTitle: true,
      ),
      body: Builder(
        builder: (context) {
          return AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: <Widget>[
                const SizedBox(height: 32),

                // Product Logo
                Hero(
                  tag: 'product-logo',
                  child: Image.asset(
                    'assets/logo_transparent.png',
                    height: 120,
                  ),
                ),

                const SizedBox(height: 48),

                // Phone Number Input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    readOnly: controller.loading,
                    autocorrect: false,
                    autofocus: true,
                    controller: controller.phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    style: textTheme.titleMedium,
                    autofillHints: controller.loading
                        ? null
                        : [AutofillHints.telephoneNumber],
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        Icons.phone_outlined,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                      errorText: controller.phoneError,
                      hintText: '请输入您的手机号...',
                      hintStyle: textTheme.bodyLarge?.copyWith(
                        color: theme.hintColor,
                      ),
                      suffixIcon: controller.codeSent
                          ? Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.tertiary,
                              size: 32,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Request Code Button (shown only if code not sent yet)
                if (!controller.codeSent)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: controller.loading
                          ? null
                          : controller.requestVerificationCode,
                      child: controller.loading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '发送验证码',
                              style: textTheme.titleMedium,
                            ),
                    ),
                  ),

                // Verification Code Input
                if (controller.codeSent) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: TextField(
                      readOnly: controller.loading,
                      autocorrect: false,
                      controller: controller.codeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      style: textTheme.titleMedium,
                      autofillHints: controller.loading
                          ? null
                          : [AutofillHints.oneTimeCode],
                      onSubmitted: (_) => controller.verifyAndLogin(),
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          Icons.verified_user_outlined,
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                        errorText: controller.codeError,
                        hintText: '请输入验证码...',
                        hintStyle: textTheme.bodyLarge?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Resend Code Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: TextButton(
                      onPressed: controller.loading
                          ? null
                          : controller.requestVerificationCode,
                      child: Text(
                        '重新发送验证码',
                        style: textTheme.titleSmall,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],

                // EULA Agreement Checkbox
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: CheckboxListTile(
                    value: controller.agreedToEula,
                    onChanged: controller.loading
                        ? null
                        : (_) => controller.toggleEulaAgreement(),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '我同意',
                          style: textTheme.titleMedium,
                        ),
                        TextButton(
                          onPressed: controller.loading
                              ? null
                              : controller.showEula,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            '《最终用户许可协议》',
                            style: textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    dense: false,
                  ),
                ),

                const SizedBox(height: 24),

                // Submit Button (shown only after code is sent)
                if (controller.codeSent)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        minimumSize: const Size.fromHeight(56),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed:
                          controller.loading ? null : controller.verifyAndLogin,
                      child: controller.loading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              '验证并继续',
                              style: TextStyle(
                                fontSize: textTheme.titleMedium?.fontSize,
                              ),
                            ),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}
