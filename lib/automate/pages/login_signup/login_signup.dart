/// The login/signup page.
/// User is automatically redirected to this page
/// if credentials are not found or invalid.
library;

import 'package:flutter/material.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'login_signup_view.dart';

class LoginSignup extends StatefulWidget {
  const LoginSignup({super.key});

  @override
  LoginSignupController createState() => LoginSignupController();
}

class LoginSignupController extends State<LoginSignup> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  
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
      // TODO: Implement phone verification code request
      // This would typically call your backend API to send an SMS
      await Future.delayed(const Duration(seconds: 1)); // Simulate API call
      
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
      // TODO: Implement phone verification and login logic
      // This would verify the code and either login or create a new account
      final matrix = Matrix.of(context);
      
      // Simulate verification
      await Future.delayed(const Duration(seconds: 1));
      
      // Here you would typically:
      // 1. Verify the phone number and code with your backend
      // 2. Get authentication credentials
      // 3. Login or register the user using matrix.getLoginClient()
      
      if (mounted) {
        setState(() => loading = false);
        // Navigation would happen automatically after successful login
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
