/// Psygo 配置管理
library;

/// Psygo 配置
/// 根据环境选择不同的子域名
class PsygoConfig {
  /// K8s Namespace（决定访问域名）
  /// 通过 --dart-define=K8S_NAMESPACE=dev|test|prod 指定
  /// dev: development-api.psygoai.com / development-matrix.psygoai.com
  /// test: internal-api.psygoai.com / internal-matrix.psygoai.com
  /// prod: api.psygoai.com / matrix.psygoai.com
  static const String k8sNamespace = String.fromEnvironment('K8S_NAMESPACE', defaultValue: 'dev');

  /// Psygo Assistant 后端 URL
  /// dev: https://development-api.psygoai.com/assistant
  /// test: https://internal-api.psygoai.com/assistant
  /// prod: https://api.psygoai.com/assistant
  static String get baseUrl {
    switch (k8sNamespace) {
      case 'prod':
        return 'https://api.psygoai.com/assistant';
      case 'test':
        return 'https://internal-api.psygoai.com/assistant';
      case 'dev':
      default:
        return 'https://development-api.psygoai.com/assistant';
    }
  }

  /// Psygo Assistant 集群内部 URL
  /// Synapse 调用 Push Gateway 用这个（K8s FQDN，Twisted 解析不了短名）
  static String get internalBaseUrl => 'http://automate-assistant.$k8sNamespace.svc.cluster.local:8080';

  /// Matrix Synapse Homeserver URL
  /// dev: https://development-matrix.psygoai.com
  /// test: https://internal-matrix.psygoai.com
  /// prod: https://matrix.psygoai.com
  static String get matrixHomeserver {
    switch (k8sNamespace) {
      case 'prod':
        return 'https://matrix.psygoai.com';
      case 'test':
        return 'https://internal-matrix.psygoai.com';
      case 'dev':
      default:
        return 'https://development-matrix.psygoai.com';
    }
  }

  /// Chatbot Backend URL
  /// dev: https://development-api.psygoai.com/onboarding-chatbot
  /// test: https://internal-api.psygoai.com/onboarding-chatbot
  /// prod: https://api.psygoai.com/onboarding-chatbot
  static String get chatbotBaseUrl {
    switch (k8sNamespace) {
      case 'prod':
        return 'https://api.psygoai.com/onboarding-chatbot';
      case 'test':
        return 'https://internal-api.psygoai.com/onboarding-chatbot';
      case 'dev':
      default:
        return 'https://development-api.psygoai.com/onboarding-chatbot';
    }
  }

  /// API 版本前缀
  static const String apiPrefix = '/api';

  /// 完整 API URL
  static String get apiUrl => baseUrl + apiPrefix;

  /// HTTP 超时配置
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// LLM 默认配置
  static const String defaultLLMProvider = 'openrouter';
  static const String defaultLLMModel = 'openai/gpt-5';
  static const int defaultMaxMemoryTokens = 3500000;
}
