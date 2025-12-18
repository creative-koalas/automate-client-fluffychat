/// Psygo 配置管理
library;

/// Psygo 配置
/// 假设客户端永远与 K8s 集群在同一局域网
class PsygoConfig {
  /// K8s 节点 IP（局域网访问）
  /// 通过 --dart-define=K8S_NODE_IP=192.168.x.x 指定
  static const String k8sNodeIp = String.fromEnvironment('K8S_NODE_IP', defaultValue: '127.0.0.1');

  /// K8s Namespace（决定端口前缀）
  /// 通过 --dart-define=K8S_NAMESPACE=dev|test|prod 指定
  /// dev=30xxx, test=31xxx, prod=32xxx
  static const String k8sNamespace = String.fromEnvironment('K8S_NAMESPACE', defaultValue: 'dev');

  /// 根据 namespace 获取端口前缀
  /// dev: 30, test: 31, prod: 32
  static String get _portPrefix {
    switch (k8sNamespace) {
      case 'test':
        return '31';
      case 'prod':
        return '32';
      case 'dev':
      default:
        return '30';
    }
  }

  /// NodePort 端口号（根据 namespace 动态计算）
  /// assistant-external: x0080
  /// matrix-synapse-external: x0008
  /// chatbot-backend: x0300
  static int get assistantPort => int.parse('${_portPrefix}080');
  static int get matrixPort => int.parse('${_portPrefix}008');
  static int get chatbotPort => int.parse('${_portPrefix}300');

  /// Psygo Assistant 后端 URL（K8s NodePort）
  /// 客户端直接访问用这个
  static String get baseUrl => 'http://$k8sNodeIp:$assistantPort';

  /// Psygo Assistant 集群内部 URL
  /// Synapse 调用 Push Gateway 用这个（K8s FQDN，Twisted 解析不了短名）
  static String get internalBaseUrl => 'http://automate-assistant.$k8sNamespace.svc.cluster.local:8080';

  /// Matrix Synapse Homeserver URL（K8s NodePort）
  static String get matrixHomeserver => 'http://$k8sNodeIp:$matrixPort';

  /// Chatbot Backend URL（K8s NodePort）
  static String get chatbotBaseUrl => 'http://$k8sNodeIp:$chatbotPort';

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
