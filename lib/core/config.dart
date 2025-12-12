/// Psygo 配置管理
library;

/// Psygo 配置
/// 假设客户端永远与 K8s 集群在同一局域网
class PsygoConfig {
  /// K8s 节点 IP（局域网访问）
  /// 通过 --dart-define=K8S_NODE_IP=192.168.x.x 指定
  static const String k8sNodeIp = String.fromEnvironment('K8S_NODE_IP', defaultValue: '127.0.0.1');

  /// Psygo Assistant 后端 URL（K8s NodePort: 32469）
  /// 客户端直接访问用这个
  static const String baseUrl = 'http://$k8sNodeIp:32469';

  /// Psygo Assistant 集群内部 URL
  /// Synapse 调用 Push Gateway 用这个（K8s FQDN，Twisted 解析不了短名）
  static const String internalBaseUrl = 'http://automate-assistant.default.svc.cluster.local:8080';

  /// Matrix Synapse Homeserver URL（K8s NodePort: 30008）
  static const String matrixHomeserver = 'http://$k8sNodeIp:30008';

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
