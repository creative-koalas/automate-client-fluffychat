/// The login/signup page.
/// User is automatically redirected to this page
/// if credentials are not found or invalid.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/automate/backend.dart';
import 'login_signup_view.dart';

class LoginSignup extends StatefulWidget {
  const LoginSignup({super.key});

  @override
  LoginSignupController createState() => LoginSignupController();
}

class LoginSignupController extends State<LoginSignup> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  final AutomateBackend backend = AutomateBackend();

  String? phoneError;
  String? codeError;
  bool loading = false;
  bool agreedToEula = false;
  bool codeSent = false;

  void toggleEulaAgreement() {
    setState(() => agreedToEula = !agreedToEula);
  }

  void requestVerificationCode() async {
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
      // Call backend API to send verification code
      await backend.sendVerificationCode(phoneController.text);

      setState(() {
        codeSent = true;
        loading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发送验证码！')),
        );
      }
    } catch (e) {
      setState(() {
        phoneError = e.toString();
        loading = false;
      });
    }
  }

  void verifyAndLogin() async {
    if (phoneController.text.isEmpty) {
      setState(() => phoneError = '请输入您的手机号');
      return;
    }

    if (codeController.text.isEmpty) {
      setState(() => codeError = '请输入验证码');
      return;
    }

    if (!agreedToEula) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请同意用户协议')),
      );
      return;
    }

    setState(() {
      phoneError = null;
      codeError = null;
      loading = true;
    });

    try {
      final matrix = Matrix.of(context);

      // Verify the phone number and code with backend
      final authResponse = await backend.verifyCode(
        phoneController.text,
        codeController.text,
      );

      // TODO: Use authResponse.token to login or register the user
      // This would typically involve calling matrix.getLoginClient() with
      // the credentials obtained from the backend

      if (mounted) {
        setState(() => loading = false);

        // Redirect to onboarding chatbot if it's a new user
        if (authResponse.isNewUser) {
          context.go('/onboarding-chatbot');
        } else {
          // For existing users, navigate to rooms
          context.go('/rooms');
        }
      }
    } catch (e) {
      setState(() {
        codeError = e.toString();
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    phoneController.dispose();
    codeController.dispose();
    backend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoginSignupView(this);
}

extension on String {
  static final RegExp _phoneRegex =
      RegExp(r'^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]*$');

  bool get isPhoneNumber => _phoneRegex.hasMatch(this);
}
