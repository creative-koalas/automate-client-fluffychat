import 'dart:io';

import 'package:dio/dio.dart';
import 'package:psygo/backend/exceptions.dart';
import 'package:psygo/l10n/l10n.dart';

String friendlyBackendErrorMessage(Object error, L10n l10n) {
  final rawMessage = _extractMessage(error);
  final message = rawMessage.trim();
  final lower = message.toLowerCase();

  // 邀请码业务提示（优先返回明确文案）
  if (_hasAny(lower, const ['不能绑定自己的邀请码', '不能綁定自己的邀請碼', 'self bind'])) {
    return l10n.invitationErrorSelfBind;
  }
  if (_hasAny(lower, const ['您已绑定过邀请码', '已綁定過邀請碼', 'already bound', '不可重复绑定'])) {
    return l10n.invitationErrorAlreadyBound;
  }
  if (_hasAny(lower, const ['已存在邀请关系', '已存在邀請關係', 'mutual binding'])) {
    return l10n.invitationErrorMutualBinding;
  }
  if (_hasAny(lower, const ['邀请码不存在', '邀請碼不存在', 'invitation not found'])) {
    return l10n.invitationErrorNotFound;
  }
  if (_hasAny(lower, const ['邀请码格式错误', '邀請碼格式錯誤', 'invalid invitation code'])) {
    return l10n.invitationCodeInvalid;
  }
  if (_hasAny(lower, const [
    'failed to check binding',
    'failed to check mutual binding',
    'failed to count invitees',
    'failed to create binding',
    'bind invitation failed',
    'get invitation info failed',
    'failed to get invitation info',
    'failed to backfill invitation code',
    'failed to list invitation bindings',
    'failed to list bindings',
  ])) {
    return l10n.invitationErrorTemporarilyUnavailable;
  }

  // 鉴权提示
  if (_hasAny(lower, const [
    'not logged in',
    'unauthorized',
    'invalid token',
    'user id not found',
    'invalid user id format',
  ])) {
    return l10n.authMatrixCredentialsMissing;
  }

  // 联系人邀请链路优先透传后端异常，避免被通用文案覆盖。
  if (message.isNotEmpty && _shouldPreserveContactInviteMessage(lower)) {
    return message;
  }

  // 网络与连接异常
  if (error is DioException) {
    if (_isNetworkDioError(error) || _hasAny(lower, const ['timeout', 'network'])) {
      return l10n.networkError;
    }
  }
  if (error is SocketException ||
      error is HandshakeException ||
      _hasAny(lower, const [
        'socketexception',
        'handshakeexception',
        'failed host lookup',
        'connection reset',
        'timed out',
        'timeout',
      ])) {
    return l10n.networkError;
  }

  return l10n.oopsSomethingWentWrong;
}

String _extractMessage(Object error) {
  if (error is AutomateBackendException) {
    return error.message;
  }
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final msg = data['message']?.toString();
      if (msg != null && msg.trim().isNotEmpty) {
        return msg;
      }
    }
    if (error.message != null && error.message!.trim().isNotEmpty) {
      return error.message!;
    }
    return error.toString();
  }
  return error.toString();
}

bool _hasAny(String source, List<String> patterns) {
  for (final pattern in patterns) {
    if (source.contains(pattern)) return true;
  }
  return false;
}

bool _shouldPreserveContactInviteMessage(String message) {
  return _hasAny(message, const [
    'contact invite',
    '邀请链接',
    '邀请信息',
    '接受邀请',
    '完成邀请',
    'create contact invite failed',
    'preview contact invite failed',
    'claim contact invite failed',
    'complete contact invite failed',
    'failed to create contact invite',
    'failed to load contact invite',
    'failed to claim contact invite',
    'failed to complete contact invite',
    'accepted_room_id',
    'accepted room id',
    'token is required',
  ]);
}

bool _isNetworkDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return true;
    case DioExceptionType.badResponse:
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return false;
  }
}
