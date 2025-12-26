/// Psygo 配置管理
library;

/// Psygo 配置
/// 所有环境相关配置通过 --dart-define-from-file=env.json 注入
class PsygoConfig {
  /// K8s Namespace
  static const String k8sNamespace = String.fromEnvironment('K8S_NAMESPACE', defaultValue: 'dev');

  /// Psygo Assistant 后端 URL
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://development-api.psygoai.com/assistant',
  );

  /// Psygo Assistant 集群内部 URL
  /// Synapse 调用 Push Gateway 用这个（K8s FQDN，Twisted 解析不了短名）
  static String get internalBaseUrl => 'http://automate-assistant.$k8sNamespace.svc.cluster.local:8080';

  /// Matrix Synapse Homeserver URL
  static const String matrixHomeserver = String.fromEnvironment(
    'MATRIX_HOMESERVER',
    defaultValue: 'https://development-matrix.psygoai.com',
  );

  /// Chatbot Backend URL
  static const String chatbotBaseUrl = String.fromEnvironment(
    'CHATBOT_BASE_URL',
    defaultValue: 'https://development-api.psygoai.com/onboarding-chatbot',
  );

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
