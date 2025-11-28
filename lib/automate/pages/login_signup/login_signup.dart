/// The main login page with one-click login.
/// User is automatically redirected to this page if credentials are not found or invalid.
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:automate/widgets/matrix.dart';
import 'package:automate/automate/backend/backend.dart';
import 'package:automate/automate/services/one_click_login.dart';
import 'login_signup_view.dart';

class LoginSignup extends StatefulWidget {
  const LoginSignup({super.key});

  @override
  LoginSignupController createState() => LoginSignupController();
}

class LoginSignupController extends State<LoginSignup> {
  AutomateApiClient get backend => context.read<AutomateApiClient>();

  String? phoneError;
  bool loading = false;
  bool agreedToEula = false;

  void toggleEulaAgreement() {
    setState(() => agreedToEula = !agreedToEula);
  }

  /// One-click login (Aliyun Official SDK)
  void oneClickLogin() async {
    // Web platform doesn't support one-click login
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网页版暂不支持一键登录，请点击下方"登录其他账号"')),
      );
      return;
    }

    if (!await _ensureEulaAccepted()) {
      return;
    }

    setState(() {
      phoneError = null;
      loading = true;
    });

    try {
      // 阿里云控制台获取的密钥
      const secretKey = 'Fc9xB89wBqq7tuq8i0iMIvo5BHWoUj5M775f+2dvooScxIqhsragIsckpislAhTLHUcyfi7dLcTA7EQ6yqMtadLpXLWPQelBPeW6f2iHpz06CCuG832/fQonJj9A3+/Urw05pmL15jgwN7T2blb7KzX4nmOJaSsuuE29kt13KegyS83IoiqFNI+MTzWdig45BMkzEic8yFjynMpgFew77/T4s91GT/WrAf56x+ofUn4uOmRrvBeIUF9zWHhVz8jTyarWHsC+i79/l89zVrupL3LNJJfkreYdkI7b3RBqYhN1WYf0+7YzOPWPTNj7OxeM';

      debugPrint('=== 使用官方 SDK 进行一键登录 ===');

      // 执行完整的一键登录流程
      final loginToken = await OneClickLoginService.performOneClickLogin(
        secretKey: secretKey,
        timeout: 10000,
      );

      debugPrint('=== 发送 token 到后端 ===');
      Matrix.of(context);
      final authResponse = await backend.loginOrSignup(
        '', // phone is empty for one-click login
        '', // code is empty for one-click login
        fusionToken: loginToken,
      );
      debugPrint('后端响应: isNewUser=${authResponse.isNewUser}');

      if (mounted) {
        setState(() => loading = false);

        // Redirect to onboarding chatbot if it's a new user
        if (authResponse.isNewUser) {
          context.go('/onboarding-chatbot');
        } else {
          context.go('/rooms');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('一键登录错误: $e');
      debugPrint('堆栈: $stackTrace');
      setState(() {
        phoneError = e.toString();
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

  void showEula() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const EulaBottomSheet(),
    );

    if (result == true) {
      setState(() => agreedToEula = true);
    }
  }

  @override
  Widget build(BuildContext context) => LoginSignupView(this);
}

class EulaBottomSheet extends StatelessWidget {
  const EulaBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '服务协议与隐私政策',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Text.rich(
                TextSpan(
                  children: _parseMarkdown(_eulaText, theme),
                ),
              ),
            ),
          ),
          
          const Divider(height: 1),
          
          // Footer
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('同意并继续'),
            ),
          ),
        ],
      ),
    );
  }

  // Simple Markdown Parsing Logic for EULA
  List<InlineSpan> _parseMarkdown(String text, ThemeData theme) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');

    for (var line in lines) {
      if (line.startsWith('# ')) {
        // H1
        spans.add(TextSpan(
          text: '${line.substring(2)}\n\n',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ));
      } else if (line.startsWith('## ')) {
        // H2
        spans.add(TextSpan(
          text: '${line.substring(3)}\n\n',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ));
      } else if (line.startsWith('- ')) {
        // Bullet Point
        spans.add(WidgetSpan(
          child: Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                Expanded(child: Text.rich(TextSpan(children: _parseInline(line.substring(2), theme)))),
              ],
            ),
          ),
        ));
        spans.add(const TextSpan(text: '\n'));
      } else if (line.trim().isEmpty) {
        // Empty Line
         spans.add(const TextSpan(text: '\n'));
      } else {
        // Paragraph
        spans.add(TextSpan(
          children: _parseInline(line, theme),
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ));
        spans.add(const TextSpan(text: '\n\n'));
      }
    }
    return spans;
  }

  List<InlineSpan> _parseInline(String text, ThemeData theme) {
    final spans = <InlineSpan>[];
    final parts = text.split('**');
    
    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        // Normal text
        spans.add(TextSpan(text: parts[i]));
      } else {
        // Bold text
        spans.add(TextSpan(
          text: parts[i],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      }
    }
    return spans;
  }
}

const String _eulaText = '''
# 用户服务协议

**生效日期：2023年10月1日**

欢迎您使用 Automate（以下简称“本服务”）。本协议是您与 Automate 运营方（以下简称“我们”）之间关于您使用本服务所订立的协议。

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
一旦发现您违反本协议的规定，我们有权不经通知单方采取包��但不限于限制、暂停或终止您使用本服务、封禁账号等措施，并追究您的法律责任。

## 8. 其他
- 本协议的效力、解释及纠纷的解决，适用于中华人民共和国法律。
- 若您和我们之间发生任何纠纷或争议，首先应友好协商解决；协商不成的，您同意将纠纷或争议提交至我们所在地有管辖权的民法院管辖。
''';
