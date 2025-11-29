/// Phone number + verification code login page.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:automate/widgets/layouts/login_scaffold.dart';
import 'package:automate/automate/backend/backend.dart';
import 'package:automate/automate/pages/login_signup/login_signup.dart' show PolicyBottomSheet;

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  PhoneLoginController createState() => PhoneLoginController();
}

class PhoneLoginController extends State<PhoneLoginPage> {
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

    setState(() {
      phoneError = null;
      codeError = null;
      loading = true;
    });

    try {
      final authResponse = await backend.loginOrSignup(
        phoneController.text,
        codeController.text,
      );

      if (mounted) {
        setState(() => loading = false);

        // Redirect based on onboarding status
        if (authResponse.onboardingCompleted) {
          // Already completed onboarding, go to main page
          context.go('/rooms');
        } else {
          // Need to complete onboarding chatbot first
          context.go('/onboarding-chatbot');
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

    final shouldAccept = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '服务协议与隐私政策',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                text: '请您务必审慎阅读、充分理解',
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: '“用户协议”',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  const TextSpan(text: '和'),
                  TextSpan(
                    text: '“隐私政策”',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  const TextSpan(text: '各条款。点击“同意并继续”代表您已阅读并同意全部内容。'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text('同意并继续'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('不同意'),
            ),
            const SizedBox(height: 16),
          ],
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
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return LoginScaffold(
      appBar: null,
      body: Stack(
        children: [
          // 1. Back Button (Fixed at top-left)
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

          // 2. Main Content
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: 20),
                    
                    // Hero Icon
                    Icon(
                      Icons.lock_person_outlined,
                      size: 80,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),

                    // Title Section
                    Text(
                      '手机号登录',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '欢迎回来！请验证您的手机号以继续。',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Phone Number Input
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
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                        ),
                        errorText: phoneError,
                        suffixIcon: codeSent
                            ? Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Verification Code Input
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
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
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

                    // EULA Agreement Checkbox
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: agreedToEula,
                            onChanged: loading
                                ? null
                                : (_) => toggleEulaAgreement(),
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
                                      onTap: loading ? null : showEula,
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
                                      onTap: loading ? null : showPrivacyPolicy,
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

                    const SizedBox(height: 24),

                    // Request Code Button (shown only if code not sent yet)
                    if (!codeSent)
                      FilledButton.tonal(
                        onPressed: loading ? null : requestVerificationCode,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('获取验证码', style: TextStyle(fontSize: 16)),
                      ),

                    // Submit Button
                    if (codeSent)
                      FilledButton(
                        onPressed: loading ? null : verifyAndLogin,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                          shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
                        ),
                        child: loading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '登录 / 注册',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    
                    const SizedBox(height: 24),
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
一旦发现您违反本协议的规定，我们有权不经通知单方采取包括但不限于限制、暂停或终止您使用本服务、封禁账号等措施，并追究您的法律责任。

## 8. 其他
- 本协议的效力、解释及纠纷的解决，适用于中华人民共和国法律。
- 若您和我们之间发生任何纠纷或争议，首先应友好协商解决；协商不成的，您同意将纠纷或争议提交至我们所在地有管辖权的人民法院管辖。
''';

const String _privacyPolicyText = '''
# 隐私政策

**生效日期：2023年10月1日**

Automate（以下简称"我们"）非常重视用户的隐私保护。本隐私政策旨在向您说明我们如何收集、使用、存储和保护您的个人信息。

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

extension on String {
  static final RegExp _phoneRegex =
      RegExp(r'^[+]*[(]{0,1}[0-9]{1,4}[)]{0,1}[-\s\./0-9]*$');

  bool get isPhoneNumber => _phoneRegex.hasMatch(this);
}
