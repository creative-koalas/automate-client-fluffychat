import 'package:flutter/material.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'login_signup.dart';

class LoginSignupView extends StatelessWidget {
  final LoginSignupController controller;

  const LoginSignupView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LoginScaffold(
      appBar: AppBar(
        title: const Text('Login / Sign Up'),
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
                    autofillHints: controller.loading 
                        ? null 
                        : [AutofillHints.telephoneNumber],
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.phone_outlined),
                      errorText: controller.phoneError,
                      hintText: '+1 234 567 8900',
                      labelText: 'Phone Number',
                      suffixIcon: controller.codeSent
                          ? const Icon(Icons.check_circle, color: Colors.green)
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
                      onPressed: controller.loading 
                          ? null 
                          : controller.requestVerificationCode,
                      child: controller.loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send Verification Code'),
                    ),
                  ),
                
                if (controller.codeSent) ...[
                  const SizedBox(height: 8),
                  
                  // Verification Code Input
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: TextField(
                      readOnly: controller.loading,
                      autocorrect: false,
                      controller: controller.codeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: controller.loading 
                          ? null 
                          : [AutofillHints.oneTimeCode],
                      onSubmitted: (_) => controller.verifyAndLogin(),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        errorText: controller.codeError,
                        hintText: '123456',
                        labelText: 'Verification Code',
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
                      child: const Text('Resend Code'),
                    ),
                  ),
                ],
                
                const SizedBox(height: 32),
                
                // EULA Agreement Checkbox
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: CheckboxListTile(
                    value: controller.agreedToEula,
                    onChanged: controller.loading 
                        ? null 
                        : (_) => controller.toggleEulaAgreement(),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I agree to the End User License Agreement (EULA)',
                      style: TextStyle(fontSize: 14),
                    ),
                    dense: true,
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
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: controller.loading || !controller.agreedToEula
                          ? null
                          : controller.verifyAndLogin,
                      child: controller.loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Verify and Continue'),
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
