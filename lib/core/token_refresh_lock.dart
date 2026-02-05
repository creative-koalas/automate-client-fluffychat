/// Token 刷新锁
/// 确保同一时间只有一个 token 刷新操作在进行
/// 其他等待者会复用刷新结果
library;

import 'dart:async';

/// Token 刷新结果
class TokenRefreshResult {
  final bool success;
  final Object? error;

  const TokenRefreshResult.success() : success = true, error = null;
  const TokenRefreshResult.failure(this.error) : success = false;
}

class TokenRefreshLock {
  static Completer<TokenRefreshResult>? _completer;

  /// 执行 token 刷新操作
  ///
  /// 如果已有刷新在进行中，等待其完成并返回相同的结果。
  /// 刷新成功返回 true，失败返回 false。
  ///
  /// [action] 应该是实际执行刷新的函数，成功时正常返回，失败时抛出异常。
  static Future<bool> run(Future<void> Function() action) async {
    // 如果已有刷新在进行中，等待其完成
    final existing = _completer;
    if (existing != null) {
      final result = await existing.future;
      return result.success;
    }

    // 创建新的 Completer
    final completer = Completer<TokenRefreshResult>();
    _completer = completer;

    try {
      await action();
      completer.complete(const TokenRefreshResult.success());
      return true;
    } catch (e) {
      completer.complete(TokenRefreshResult.failure(e));
      return false;
    } finally {
      // 清理
      if (identical(_completer, completer)) {
        _completer = null;
      }
    }
  }

  /// 等待任何正在进行的刷新操作完成
  /// 返回刷新是否成功
  static Future<bool> wait() async {
    final existing = _completer;
    if (existing != null) {
      final result = await existing.future;
      return result.success;
    }
    return true; // 没有刷新在进行，视为成功
  }

  /// 检查是否有刷新正在进行
  static bool get isRefreshing => _completer != null;
}
