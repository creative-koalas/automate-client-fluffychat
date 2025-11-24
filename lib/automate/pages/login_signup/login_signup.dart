/// The login/signup page.
/// User is automatically redirected to this page
/// if credentials are not found or invalid.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/automate/backend/backend.dart';
import 'login_signup_view.dart';

class LoginSignup extends StatefulWidget {
  const LoginSignup({super.key});

  @override
  LoginSignupController createState() => LoginSignupController();
}

class LoginSignupController extends State<LoginSignup> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  AutomateApiClient get backend => context.read<AutomateApiClient>();

  String? phoneError;
  String? codeError;
  bool loading = false;
  bool agreedToEula = false;
  bool codeSent = false;

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
      Matrix.of(context);

      // Verify the phone number and code with backend
      final authResponse = await backend.loginOrSignup(
        phoneController.text,
        codeController.text,
      );

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

  Future<bool> _ensureEulaAccepted() async {
    if (agreedToEula) return true;

    final shouldAccept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同意最终用户许可协议'),
        content: const Text('继续操作前，请阅读并同意《最终用户许可协议》。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('同意'),
          ),
        ],
      ),
    );

    if (shouldAccept == true) {
      setState(() => agreedToEula = true);
      return true;
    }

    return false;
  }

  void showEula() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最终用户许可协议'),
        content: const SingleChildScrollView(
          child: Text(
            '这是示例协议内容，占位说明了用户在使用本产品前需阅读并同意的条款。'
            '实际应用中请在此处填充完整的最终用户许可协议，涵盖用户权利、'
            '隐私政策、数据使用、责任限制和服务条款等信息。'
            '\n\n点击“同意”表示您已阅读并接受全部条款。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => agreedToEula = true);
            },
            child: const Text('同意'),
          ),
        ],
      ),
    );
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
