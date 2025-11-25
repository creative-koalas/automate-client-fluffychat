import 'dart:async';
import 'dart:io';

/// 网络请求重试帮助类
/// 用于自动重试失败的网络请求
class RetryHelper {
  /// 默认重试次数
  static const int defaultMaxRetries = 2;

  /// 默认重试延迟（毫秒）
  static const int defaultRetryDelayMs = 3000;

  /// 执行带重试的异步操作
  /// [operation] 要执行的异步操作
  /// [maxRetries] 最大重试次数
  /// [retryDelayMs] 重试延迟（毫秒）
  /// [shouldRetry] 可选的自定义重试条件判断函数
  /// [onRetry] 重试时的回调
  static Future<T> withRetry<T>({
    required Future<T> Function() operation,
    int maxRetries = defaultMaxRetries,
    int retryDelayMs = defaultRetryDelayMs,
    bool Function(Exception)? shouldRetry,
    void Function(int attempt, Exception error)? onRetry,
  }) async {
    int attempts = 0;
    Exception? lastException;

    while (attempts <= maxRetries) {
      try {
        return await operation();
      } on Exception catch (e) {
        lastException = e;
        attempts++;

        // 检查是否应该重试
        final isRetryable = shouldRetry?.call(e) ?? _isRetryableError(e);

        if (attempts <= maxRetries && isRetryable) {
          // 通知重试回调
          onRetry?.call(attempts, e);

          // 指数退避延迟
          final delay = retryDelayMs * attempts;
          await Future.delayed(Duration(milliseconds: delay));
        } else {
          // 不再重试，抛出异常
          break;
        }
      }
    }

    // 所有重试都失败了
    throw lastException!;
  }

  /// 判断错误是否可重试
  static bool _isRetryableError(Exception e) {
    // 网络相关错误可重试
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is HttpException) return true;

    // 检查错误消息中是否包含网络相关关键字
    final message = e.toString().toLowerCase();
    if (message.contains('socket')) return true;
    if (message.contains('connection')) return true;
    if (message.contains('timeout')) return true;
    if (message.contains('network')) return true;
    if (message.contains('unreachable')) return true;

    // HTTP 5xx 服务器错误可重试
    if (message.contains('500') ||
        message.contains('502') ||
        message.contains('503') ||
        message.contains('504')) {
      return true;
    }

    return false;
  }
}
