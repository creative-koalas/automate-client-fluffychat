import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import '../models/force_update_status.dart';
import '../models/maintenance_status.dart';
import '../services/force_update_bus.dart';
import '../services/maintenance_status_bus.dart';
import 'auth_state.dart';
import 'exceptions.dart';
import '../core/config.dart';
import '../core/token_manager.dart';
import '../utils/auth_device_identity.dart';
import '../utils/custom_http_client.dart';

enum TokenRefreshOutcome { success, transientFailure, invalidSession }

class PsygoApiClient {
  PsygoApiClient(this.auth, {Dio? dio})
      : _dio = dio ?? CustomHttpClient.createDio() {
    _dio.options.connectTimeout = PsygoConfig.connectTimeout;
    _dio.options.receiveTimeout = PsygoConfig.receiveTimeout;
    _dio.options.sendTimeout = PsygoConfig.connectTimeout;
    // 设置默认请求头
    _dio.options.headers['Content-Type'] = 'application/json';
    _dio.interceptors.add(_buildAuthInterceptor());
  }

  /// 构建认证拦截器，支持 401 自动重试
  InterceptorsWrapper _buildAuthInterceptor() {
    return InterceptorsWrapper(
      onResponse: (response, handler) {
        _captureMaintenanceFromResponse(response);
        _captureForceUpdateFromResponse(response);
        handler.next(response);
      },
      onError: (error, handler) async {
        _captureMaintenanceFromResponse(error.response);
        _captureForceUpdateFromResponse(error.response);

        // 只处理 401 错误
        if (error.response?.statusCode != 401) {
          return handler.next(error);
        }

        // 检查是否已经是重试请求（避免无限循环）
        final options = error.requestOptions;
        if (options.extra['_retried'] == true) {
          await auth.markLoggedOut();
          return handler.next(error);
        }

        // 尝试刷新 token
        debugPrint('[API] 401 received, attempting token refresh...');
        final refreshOutcome = await refreshAccessTokenWithOutcome();

        if (refreshOutcome != TokenRefreshOutcome.success) {
          if (refreshOutcome == TokenRefreshOutcome.invalidSession) {
            debugPrint(
              '[API] Token refresh failed with invalid session, logging out',
            );
            await auth.markLoggedOut();
          } else {
            debugPrint(
              '[API] Token refresh failed due to transient error, keep session',
            );
          }
          return handler.next(error);
        }

        // 刷新成功，重试原请求
        debugPrint('[API] Token refreshed, retrying request...');
        try {
          final newToken = await TokenManager.instance.getAccessToken(
            autoRefresh: false,
          );
          options.headers['Authorization'] = 'Bearer $newToken';
          options.extra['_retried'] = true;

          final response = await _dio.fetch(options);
          return handler.resolve(response);
        } catch (retryError) {
          debugPrint('[API] Retry failed: $retryError');
          return handler.next(error);
        }
      },
    );
  }

  final PsygoAuthState auth;
  final Dio _dio;
  static const Set<int> _unauthorizedCodes = {10002, 10003};

  Future<void> _syncAuthState() async {
    await auth.load();
  }

  bool _isMaintenanceStatusPath(String path) {
    final normalizedPath = Uri.tryParse(path)?.path ?? path;
    return normalizedPath.endsWith('/api/maintenance/status') ||
        normalizedPath.endsWith('/api/v1/maintenance/status');
  }

  void _captureMaintenanceFromResponse(Response<dynamic>? response) {
    if (response == null) {
      return;
    }

    MaintenanceStatusSnapshot? status;
    if (_isMaintenanceStatusPath(response.requestOptions.path)) {
      status = MaintenanceStatusSnapshot.tryParsePublicPayload(response.data);
    } else if (response.statusCode == 503) {
      status = MaintenanceStatusSnapshot.tryParseClosedErrorPayload(
        response.data,
      );
    }

    if (status != null) {
      MaintenanceStatusBus.instance.publish(status);
    }
  }

  void _captureForceUpdateFromResponse(Response<dynamic>? response) {
    if (response == null) {
      return;
    }
    final snapshot = ForceUpdateSnapshot.tryParseRequiredPayload(
      response.data,
      source: ForceUpdateSnapshot.sourceResponseInterceptor,
      httpStatus: response.statusCode,
      fallbackMessage: response.statusMessage,
    );
    if (snapshot != null) {
      ForceUpdateBus.instance.publish(snapshot);
    }
  }

  int? _readBusinessCode(Response<Map<String, dynamic>> response) {
    final code = (response.data ?? const {})['code'];
    if (code is int) {
      return code;
    }
    if (code is String) {
      return int.tryParse(code);
    }
    return null;
  }

  bool _isUnauthorizedCode(int? code) {
    return code != null && _unauthorizedCodes.contains(code);
  }

  Future<MaintenanceStatusSnapshot> _fetchMaintenanceStatusAt(
    String path,
  ) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '${PsygoConfig.baseUrl}$path',
    );

    final status = MaintenanceStatusSnapshot.tryParsePublicPayload(res.data);
    if (res.statusCode != 200 || status == null) {
      throw AutomateBackendException(
        'Failed to get maintenance status',
        statusCode: res.statusCode,
      );
    }

    MaintenanceStatusBus.instance.publish(status);
    return status;
  }

  Future<Response<Map<String, dynamic>>> _requestWithAuthRetry(
    Future<Response<Map<String, dynamic>>> Function(String token) request,
  ) async {
    await _syncAuthState();
    final token = auth.primaryToken;
    if (token == null || token.isEmpty) {
      throw AutomateBackendException('Not logged in');
    }

    var response = await request(token);
    final firstCode = _readBusinessCode(response);
    if (!_isUnauthorizedCode(firstCode)) {
      return response;
    }

    debugPrint(
      '[API] Unauthorized code=$firstCode, attempting token refresh...',
    );
    final refreshOutcome = await refreshAccessTokenWithOutcome();
    if (refreshOutcome != TokenRefreshOutcome.success) {
      if (refreshOutcome == TokenRefreshOutcome.invalidSession) {
        await auth.markLoggedOut();
      }
      return response;
    }

    await _syncAuthState();
    final refreshedToken = auth.primaryToken;
    if (refreshedToken == null || refreshedToken.isEmpty) {
      return response;
    }

    response = await request(refreshedToken);
    return response;
  }

  /// 发送短信验证码。
  /// 后端应按 `phone + auth_device_id` 做 60 秒限频，避免不同设备互相阻塞。
  Future<void> sendVerificationCode(String phone) async {
    Response<Map<String, dynamic>> res;
    try {
      final authDevicePayload = await AuthDeviceIdentity.buildRequestPayload();
      res = await _dio.post<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/auth/send-sms-code',
        data: {'phone': phone, ...authDevicePayload},
      );
    } on DioException catch (e) {
      debugPrint(
        '[API] sendVerificationCode DioException: ${e.type}, ${e.message}',
      );
      debugPrint('[API] DioException error: ${e.error}');

      final responseData = e.response?.data;
      var errorMsg = '验证码发送失败，请稍后重试';

      // 检查是否是 TLS/SSL 证书错误
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        final errorStr = e.error?.toString() ?? '';
        if (errorStr.contains('CERTIFICATE_VERIFY_FAILED') ||
            errorStr.contains('HandshakeException') ||
            errorStr.contains('certificate')) {
          errorMsg = '网络安全连接失败，请检查网络或更新系统';
          debugPrint('[API] SSL/TLS certificate error detected');
        }
      }

      if (responseData is Map<String, dynamic>) {
        errorMsg = responseData['message']?.toString() ?? errorMsg;
      }
      throw AutomateBackendException(
        errorMsg,
        statusCode: e.response?.statusCode,
      );
    }

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? '验证码发送失败',
        statusCode: res.statusCode,
      );
    }
  }

  Future<MaintenanceStatusSnapshot> getMaintenanceStatus() async {
    try {
      return await _fetchMaintenanceStatusAt('/api/maintenance/status');
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        rethrow;
      }
    }

    return _fetchMaintenanceStatusAt('/api/v1/maintenance/status');
  }

  /// 短信验证码登录
  Future<AuthResponse> smsLogin(String phone, String code) async {
    final authDevicePayload = await AuthDeviceIdentity.buildRequestPayload();
    final res = await _dio.post<Map<String, dynamic>>(
      '${PsygoConfig.baseUrl}/api/auth/sms-login',
      data: {'phone': phone, 'code': code, ...authDevicePayload},
    );
    return _handleAuthResponse(res, '登录失败');
  }

  /// 一键登录（阿里云）
  Future<AuthResponse> oneClickLogin(String accessToken) async {
    final authDevicePayload = await AuthDeviceIdentity.buildRequestPayload();
    final res = await _dio.post<Map<String, dynamic>>(
      '${PsygoConfig.baseUrl}/api/auth/one-click-login',
      data: {'access_token': accessToken, ...authDevicePayload},
    );
    return _handleAuthResponse(res, '登录失败');
  }

  Future<AuthResponse> _handleAuthResponse(
    Response<Map<String, dynamic>> res,
    String fallbackMessage,
  ) async {
    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? fallbackMessage,
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    final token = (respData['access_token'] as String?)?.trim() ?? '';
    final userId = (respData['user_id'] as String?)?.trim() ?? '';
    if (token.isEmpty || userId.isEmpty) {
      throw AutomateBackendException(
        'Invalid auth response: missing access_token or user_id',
      );
    }

    final rawRefreshToken = (respData['refresh_token'] as String?)?.trim();
    final refreshToken = (rawRefreshToken != null && rawRefreshToken.isNotEmpty)
        ? rawRefreshToken
        : null;
    final hasRefreshToken = refreshToken != null;

    final rawExpiresIn = respData['expires_in'];
    final expiresIn = rawExpiresIn is int
        ? rawExpiresIn
        : (rawExpiresIn is num
            ? rawExpiresIn.toInt()
            : int.tryParse(rawExpiresIn?.toString() ?? ''));

    final authResponse = AuthResponse(
      token: token,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
      userId: userId,
      phone: respData['phone'] as String? ?? '',
      matrixAccessToken: respData['matrix_access_token'] as String?,
      matrixUserId: respData['matrix_user_id'] as String?,
      matrixDeviceId: respData['matrix_device_id'] as String?,
    );

    debugPrint(
      '[API] Auth login response parsed: '
      'has_refresh_token=$hasRefreshToken, '
      'expires_in=${authResponse.expiresIn}, '
      'platform=${AuthDeviceIdentity.platformName}',
    );

    if ((authResponse.expiresIn ?? 0) > 0 &&
        authResponse.refreshToken == null) {
      debugPrint(
        '[API] Auth response missing refresh_token '
        '(platform=${AuthDeviceIdentity.platformName}, expires_in=${authResponse.expiresIn})',
      );
    }

    final rawOnboardingCompleted = respData['onboarding_completed'];
    final onboardingCompleted = rawOnboardingCompleted is bool
        ? rawOnboardingCompleted
        : (rawOnboardingCompleted is num
            ? rawOnboardingCompleted != 0
            : rawOnboardingCompleted?.toString().toLowerCase() == 'true');

    await auth.save(
      primaryToken: authResponse.token,
      userId: authResponse.userId,
      onboardingCompleted: onboardingCompleted,
      refreshToken: authResponse.refreshToken,
      expiresIn: authResponse.expiresIn,
      matrixAccessToken: authResponse.matrixAccessToken,
      matrixUserId: authResponse.matrixUserId,
      matrixDeviceId: authResponse.matrixDeviceId,
    );
    return authResponse;
  }

  /// Refresh the access token using refresh token
  /// Returns true if refresh was successful, false otherwise
  /// 委托给 TokenManager 统一处理，避免重复逻辑
  Future<TokenRefreshOutcome> refreshAccessTokenWithOutcome() async {
    final success = await TokenManager.instance.refreshAccessToken();
    await _syncAuthState();
    if (success) {
      return TokenRefreshOutcome.success;
    }

    // TokenManager 在 refresh token 无效时会清空本地 token。
    final hasAccessToken = (auth.primaryToken ?? '').isNotEmpty;
    final hasRefreshToken = (auth.refreshToken ?? '').isNotEmpty;
    if (!auth.isLoggedIn || !hasAccessToken || !hasRefreshToken) {
      return TokenRefreshOutcome.invalidSession;
    }

    return TokenRefreshOutcome.transientFailure;
  }

  Future<bool> refreshAccessToken() async {
    final outcome = await refreshAccessTokenWithOutcome();
    return outcome == TokenRefreshOutcome.success;
  }

  /// Ensure we have a valid token before making API calls
  /// Will refresh token if it's expiring soon
  /// 委托给 TokenManager，它会自动处理刷新逻辑
  Future<bool> ensureValidToken() async {
    // TokenManager.getAccessToken 会自动刷新即将过期的 token
    final token = await TokenManager.instance.getAccessToken(autoRefresh: true);
    if (token != null && token.isNotEmpty) {
      await _syncAuthState();
      return true;
    }
    return false;
  }

  /// 创建充值订单
  Future<RechargeOrderResponse> createRechargeOrder(double amount) async {
    await _syncAuthState();
    final userId = auth.userId;
    if (userId == null || userId.isEmpty) {
      throw AutomateBackendException('User ID not found');
    }

    final res = await _requestWithAuthRetry((token) {
      return _dio.post<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/payments/recharge/create',
        data: {'user_id': userId, 'total_amount': amount},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? 'Failed to create recharge order',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return RechargeOrderResponse.fromJson(respData);
  }

  /// 查询订单状态
  Future<PaymentOrder> getOrderStatus(String outTradeNo) async {
    final res = await _requestWithAuthRetry((token) {
      return _dio.get<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/payments/orders/$outTradeNo',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? 'Failed to get order status',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return PaymentOrder.fromJson(respData);
  }

  /// 提交用户反馈
  Future<void> submitFeedback({
    required String content,
    String? replyEmail,
    String? category,
    String? appVersion,
    String? deviceInfo,
    List<XFile> attachments = const [],
  }) async {
    await _syncAuthState();
    final userId = auth.userId;
    if (userId == null || userId.isEmpty) {
      throw AutomateBackendException('User ID not found');
    }

    final payload = <String, dynamic>{
      'user_id': userId,
      'content': content,
      if (replyEmail != null && replyEmail.isNotEmpty)
        'reply_email': replyEmail,
      if (category != null && category.isNotEmpty) 'category': category,
      if (appVersion != null && appVersion.isNotEmpty)
        'app_version': appVersion,
      if (deviceInfo != null && deviceInfo.isNotEmpty)
        'device_info': deviceInfo,
    };
    final useMultipart = attachments.isNotEmpty;

    final res = await _requestWithAuthRetry((token) async {
      dynamic requestData = payload;
      if (useMultipart) {
        final formData = FormData.fromMap(payload);
        for (var i = 0; i < attachments.length; i++) {
          final file = attachments[i];
          final name = file.name.trim().isNotEmpty
              ? file.name.trim()
              : 'attachment_${i + 1}';
          formData.files.add(
            MapEntry(
              'files',
              MultipartFile.fromBytes(await file.readAsBytes(), filename: name),
            ),
          );
        }
        requestData = formData;
      }

      return _dio.post<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/feedback',
        data: requestData,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? 'Failed to submit feedback',
        statusCode: res.statusCode,
      );
    }
  }

  /// 绑定邀请码
  Future<BindInvitationResponse> bindInvitation(String code) async {
    final res = await _requestWithAuthRetry((token) {
      return _dio.post<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/users/invitation/bind',
        data: {'invitation_code': code},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? '绑定邀请码失败',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return BindInvitationResponse.fromJson(respData);
  }

  Future<ContactInviteCreateResult> createContactInvite({
    String? source,
    Map<String, String>? metadata,
  }) async {
    final res = await _requestWithAuthRetry((token) {
      return _dio.post<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/contact-invites',
        data: <String, dynamic>{
          if (source != null && source.isNotEmpty) 'source': source,
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? '创建邀请链接失败',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return ContactInviteCreateResult.fromJson(respData);
  }

  Future<ContactInvitePreview> previewContactInvite(String token) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '${PsygoConfig.baseUrl}/api/contact-invites/$token/preview',
    );

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      throw AutomateBackendException(
        data['message']?.toString() ?? '获取邀请信息失败',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return ContactInvitePreview.fromJson(respData);
  }

  Future<ContactInviteClaimResult> claimContactInvite(String token) async {
    final res = await _requestWithAuthRetry((tokenValue) {
      return _dio.post<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/contact-invites/$token/claim',
        options: Options(headers: {'Authorization': 'Bearer $tokenValue'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? '接受邀请失败',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return ContactInviteClaimResult.fromJson(respData);
  }

  Future<ContactInviteCompleteResult> completeContactInvite(
    String token, {
    required String acceptedRoomId,
    Map<String, String>? metadata,
  }) async {
    final res = await _requestWithAuthRetry((tokenValue) {
      return _dio.post<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/contact-invites/$token/complete',
        data: <String, dynamic>{
          'accepted_room_id': acceptedRoomId,
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
        },
        options: Options(headers: {'Authorization': 'Bearer $tokenValue'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? '完成邀请失败',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return ContactInviteCompleteResult.fromJson(respData);
  }

  /// 获取邀请信息
  Future<InvitationInfo> getInvitationInfo() async {
    await _syncAuthState();
    final userId = auth.userId;
    if (userId == null || userId.isEmpty) {
      throw AutomateBackendException('User ID not found');
    }

    final res = await _requestWithAuthRetry((token) {
      return _dio.get<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/users/$userId/invitation',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? '获取邀请信息失败',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return InvitationInfo.fromJson(respData);
  }

  /// 提交昵称修改申请
  Future<void> submitNicknameChangeRequest(String newNickname) async {
    final res = await _requestWithAuthRetry((token) {
      return _dio.post<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/users/nickname-request',
        data: {'new_nickname': newNickname},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? 'Failed to submit nickname change',
        statusCode: res.statusCode,
      );
    }
  }

  /// 获取用户信息（包含余额）
  Future<UserInfo> getUserInfo() async {
    await _syncAuthState();
    final userId = auth.userId;
    if (userId == null || userId.isEmpty) {
      throw AutomateBackendException('User ID not found');
    }

    final res = await _requestWithAuthRetry((token) {
      return _dio.get<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/users/$userId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? 'Failed to get user info',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }
    final userData = respData;

    final balanceRes = await _requestWithAuthRetry((token) {
      return _dio.get<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/users/$userId/balance',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final balanceData = balanceRes.data ?? {};
    final balanceCode = balanceData['code'] as int? ?? -1;
    if (balanceRes.statusCode != 200 || balanceCode != 0) {
      await _handleAuthError(balanceCode);
      throw AutomateBackendException(
        balanceData['message']?.toString() ?? 'Failed to get user balance',
        statusCode: balanceRes.statusCode,
      );
    }

    final balancePayload = balanceData['data'] as Map<String, dynamic>?;
    if (balancePayload == null) {
      throw AutomateBackendException('Empty balance data');
    }
    final balanceValue = balancePayload['balance'];
    int? balance;
    if (balanceValue is num) {
      balance = balanceValue.toInt();
    } else if (balanceValue != null) {
      balance = int.tryParse(balanceValue.toString());
    }
    if (balance == null) {
      throw AutomateBackendException('Invalid balance data');
    }

    return UserInfo.fromJson(userData, creditBalance: balance);
  }

  /// 检查应用版本更新
  /// [currentVersion] 当前客户端版本号
  /// [platform] 平台：android/ios/windows/linux/macos
  Future<AppVersionResponse> checkAppVersion({
    required String currentVersion,
    required String platform,
    bool publishForceUpdate = true,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '${PsygoConfig.baseUrl}/api/app/version',
      queryParameters: {'version': currentVersion, 'platform': platform},
    );

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? 'Failed to check app version',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    final parsed = AppVersionResponse.fromJson(respData);
    if (publishForceUpdate) {
      ForceUpdateBus.instance.publish(
        ForceUpdateSnapshot(
          required: parsed.forceUpdate,
          minVersion: parsed.minSupportedVersion,
          latestVersion: parsed.latestVersion,
          downloadUrl: parsed.downloadUrl,
          changelog: parsed.changelog,
          checkedAt: DateTime.now(),
          source: ForceUpdateSnapshot.sourceVersionCheck,
        ),
      );
    }
    return parsed;
  }

  /// 获取所有激活的协议列表（公开接口，无需认证）
  /// 返回用户协议和隐私政策的 URL
  Future<List<Agreement>> getAgreements() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '${PsygoConfig.baseUrl}/api/agreements',
    );

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? 'Failed to get agreements',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as List<dynamic>?;
    if (respData == null) {
      return [];
    }

    return respData
        .whereType<Map<String, dynamic>>()
        .map((json) => Agreement.fromJson(json))
        .toList();
  }

  /// 获取用户协议接受状态（需要认证）
  /// 用于检查用户是否已同意所有激活的协议
  Future<AgreementStatus> getAgreementStatus() async {
    final res = await _requestWithAuthRetry((token) {
      return _dio.get<Map<String, dynamic>>(
        '${PsygoConfig.baseUrl}/api/agreements/status',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    });

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? 'Failed to get agreement status',
        statusCode: res.statusCode,
      );
    }

    final respData = data['data'] as Map<String, dynamic>?;
    if (respData == null) {
      throw AutomateBackendException('Empty response data');
    }

    return AgreementStatus.fromJson(respData);
  }

  /// 注销账号（用户自助注销）
  /// 级联删除：Agent、Matrix 账号、推送设备、用户记录（软删除）
  Future<void> deleteAccount() async {
    Response<Map<String, dynamic>> res;
    try {
      res = await _requestWithAuthRetry((token) {
        return _dio.delete<Map<String, dynamic>>(
          '${PsygoConfig.baseUrl}/api/users/me?confirm=true',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      });
    } on DioException catch (e) {
      final responseData = e.response?.data;
      var errorMsg = '注销失败，请稍后重试';
      if (responseData is Map<String, dynamic>) {
        errorMsg = responseData['message']?.toString() ?? errorMsg;
      }
      throw AutomateBackendException(
        errorMsg,
        statusCode: e.response?.statusCode,
      );
    }

    final data = res.data ?? {};
    final respCode = data['code'] as int? ?? -1;
    if (res.statusCode != 200 || respCode != 0) {
      await _handleAuthError(respCode);
      throw AutomateBackendException(
        data['message']?.toString() ?? '注销失败',
        statusCode: res.statusCode,
      );
    }
  }

  Future<void> _handleAuthError(int? code) async {
    if (!_isUnauthorizedCode(code)) {
      return;
    }
    // 10003 表示 refresh token 失效，必须重新登录。
    // 10002 可能是 access token 过期，先由 refresh 流程处理，避免误登出。
    if (code == 10003) {
      await auth.markLoggedOut();
      return;
    }

    await _syncAuthState();
    final hasRefreshToken = (auth.refreshToken ?? '').isNotEmpty;
    if (!hasRefreshToken) {
      await auth.markLoggedOut();
    }
  }
}

class AuthResponse {
  final String token;
  final String? refreshToken;
  final int? expiresIn;
  final String userId;
  final String phone;
  final String? matrixAccessToken;
  final String? matrixUserId;
  final String? matrixDeviceId;

  AuthResponse({
    required this.token,
    this.refreshToken,
    this.expiresIn,
    required this.userId,
    required this.phone,
    this.matrixAccessToken,
    this.matrixUserId,
    this.matrixDeviceId,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'refreshToken': refreshToken,
        'expiresIn': expiresIn,
        'userId': userId,
        'phone': phone,
        'matrixAccessToken': matrixAccessToken,
        'matrixUserId': matrixUserId,
        'matrixDeviceId': matrixDeviceId,
      };
}

/// 充值订单创建请求
class CreateRechargeOrderRequest {
  final String userId;
  final double totalAmount;

  CreateRechargeOrderRequest({required this.userId, required this.totalAmount});

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'total_amount': totalAmount,
      };
}

/// 充值订单响应
class RechargeOrderResponse {
  final String outTradeNo; // 商户订单号
  final String orderString; // 支付宝订单字符串（传给 SDK）
  final double totalAmount; // 订单金额（元）
  final int creditsAmount; // 充值积分数

  RechargeOrderResponse({
    required this.outTradeNo,
    required this.orderString,
    required this.totalAmount,
    required this.creditsAmount,
  });

  factory RechargeOrderResponse.fromJson(Map<String, dynamic> json) {
    return RechargeOrderResponse(
      outTradeNo: json['out_trade_no'] as String? ?? '',
      orderString: json['order_string'] as String? ?? '',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      creditsAmount: (json['credits_amount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 订单状态
class PaymentOrder {
  final String outTradeNo;
  final String? tradeNo;
  final String userId;
  final double totalAmount;
  final int creditsAmount;
  final String status; // pending, paid, closed, refunded
  final String? tradeStatus;
  final String? notifyTime;
  final String createdAt;
  final String updatedAt;

  PaymentOrder({
    required this.outTradeNo,
    this.tradeNo,
    required this.userId,
    required this.totalAmount,
    required this.creditsAmount,
    required this.status,
    this.tradeStatus,
    this.notifyTime,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentOrder.fromJson(Map<String, dynamic> json) {
    return PaymentOrder(
      outTradeNo: json['out_trade_no'] as String? ?? '',
      tradeNo: json['trade_no'] as String?,
      userId: json['user_id'] as String? ?? '',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      creditsAmount: (json['credits_amount'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      tradeStatus: json['trade_status'] as String?,
      notifyTime: json['notify_time'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

/// 用户信息（包含余额）
class UserInfo {
  final String id;
  final String phone;
  final String? email;
  final String? nickname;
  final String status;
  final String role;
  final String tier;
  final DateTime? invitationVerifiedAt;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final int creditBalance; // 积分余额

  UserInfo({
    required this.id,
    required this.phone,
    this.email,
    this.nickname,
    required this.status,
    required this.role,
    required this.tier,
    this.invitationVerifiedAt,
    this.lastLoginAt,
    this.createdAt,
    required this.creditBalance,
  });

  factory UserInfo.fromJson(
    Map<String, dynamic> json, {
    int creditBalance = 0,
  }) {
    DateTime? parseTime(dynamic value) {
      if (value == null) {
        return null;
      }
      return DateTime.tryParse(value.toString());
    }

    return UserInfo(
      id: json['id'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      nickname: json['nickname'] as String?,
      status: json['status'] as String? ?? '',
      role: json['role'] as String? ?? '',
      tier: json['tier'] as String? ?? '',
      invitationVerifiedAt: parseTime(json['invitation_verified_at']),
      lastLoginAt: parseTime(json['last_login_at']),
      createdAt: parseTime(json['created_at']),
      creditBalance: creditBalance,
    );
  }
}

/// 版本检查响应
class AppVersionResponse {
  final String latestVersion; // 最新版本号
  final String minSupportedVersion; // 最低支持版本
  final bool forceUpdate; // 是否强制更新
  final String? downloadUrl; // 下载链接（null 表示已是最新，链接有效期 10 分钟）
  final String? changelog; // 更新日志

  AppVersionResponse({
    required this.latestVersion,
    required this.minSupportedVersion,
    required this.forceUpdate,
    this.downloadUrl,
    this.changelog,
  });

  /// 是否有更新（强制更新即使没有下载链接也视为更新）
  bool get hasUpdate =>
      forceUpdate || (downloadUrl != null && downloadUrl!.isNotEmpty);

  factory AppVersionResponse.fromJson(Map<String, dynamic> json) {
    return AppVersionResponse(
      latestVersion: json['latest_version'] as String? ?? '',
      minSupportedVersion: json['min_supported_version'] as String? ?? '',
      forceUpdate: json['force_update'] as bool? ?? false,
      downloadUrl: json['download_url'] as String?,
      changelog: json['changelog'] as String?,
    );
  }
}

/// 协议信息
class Agreement {
  final int id;
  final String type; // terms 或 privacy
  final String version; // 版本号，如 v1.0.0
  final String url; // 协议页面 URL
  final bool isActive;

  Agreement({
    required this.id,
    required this.type,
    required this.version,
    required this.url,
    required this.isActive,
  });

  /// 是否是用户协议
  bool get isTerms => type == 'terms';

  /// 是否是隐私政策
  bool get isPrivacy => type == 'privacy';

  factory Agreement.fromJson(Map<String, dynamic> json) {
    return Agreement(
      id: json['id'] as int? ?? 0,
      type: json['type'] as String? ?? '',
      version: json['version'] as String? ?? '',
      url: json['url'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
    );
  }
}

/// 用户协议接受状态
class AgreementStatus {
  final bool allAccepted; // 是否已接受所有必需协议
  final List<AgreementAcceptance> agreements; // 各协议的接受状态

  AgreementStatus({required this.allAccepted, required this.agreements});

  factory AgreementStatus.fromJson(Map<String, dynamic> json) {
    final agreementsList = json['agreements'] as List<dynamic>? ?? [];
    return AgreementStatus(
      allAccepted: json['all_accepted'] as bool? ?? false,
      agreements: agreementsList
          .whereType<Map<String, dynamic>>()
          .map((e) => AgreementAcceptance.fromJson(e))
          .toList(),
    );
  }
}

/// 绑定邀请码响应
class BindInvitationResponse {
  final String inviterNickname;
  final int rewardCredits;

  BindInvitationResponse({
    required this.inviterNickname,
    required this.rewardCredits,
  });

  factory BindInvitationResponse.fromJson(Map<String, dynamic> json) {
    return BindInvitationResponse(
      inviterNickname: json['inviter_nickname'] as String? ?? '',
      rewardCredits: (json['reward_credits'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 邀请信息
class InvitationInfo {
  final String invitationCode;
  final bool isBound;
  final int maxInvitees;
  final int currentInvitees;
  final int rewardPerInvite;
  final List<InviteeInfo> invitees;

  InvitationInfo({
    required this.invitationCode,
    required this.isBound,
    required this.maxInvitees,
    required this.currentInvitees,
    required this.rewardPerInvite,
    required this.invitees,
  });

  bool get isFull => currentInvitees >= maxInvitees;

  factory InvitationInfo.fromJson(Map<String, dynamic> json) {
    final inviteesList = json['invitees'] as List<dynamic>? ?? [];
    return InvitationInfo(
      invitationCode: json['invitation_code'] as String? ?? '',
      isBound: json['is_bound'] as bool? ?? false,
      maxInvitees: (json['max_invitees'] as num?)?.toInt() ?? 10,
      currentInvitees: (json['current_invitees'] as num?)?.toInt() ?? 0,
      rewardPerInvite: (json['reward_per_invite'] as num?)?.toInt() ?? 0,
      invitees: inviteesList
          .whereType<Map<String, dynamic>>()
          .map((e) => InviteeInfo.fromJson(e))
          .toList(),
    );
  }
}

/// 被邀请人信息
class InviteeInfo {
  final String nickname;
  final DateTime? createdAt;

  InviteeInfo({required this.nickname, this.createdAt});

  factory InviteeInfo.fromJson(Map<String, dynamic> json) {
    return InviteeInfo(
      nickname: json['nickname'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

class ContactInviteCreateResult {
  final String inviteToken;
  final String inviteUrl;
  final DateTime? expiresAt;

  ContactInviteCreateResult({
    required this.inviteToken,
    required this.inviteUrl,
    this.expiresAt,
  });

  factory ContactInviteCreateResult.fromJson(Map<String, dynamic> json) {
    return ContactInviteCreateResult(
      inviteToken: json['invite_token'] as String? ?? '',
      inviteUrl: json['invite_url'] as String? ?? '',
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
    );
  }
}

class ContactInviteInviterPreview {
  final String userId;
  final String displayName;
  final String avatarUrl;

  ContactInviteInviterPreview({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });

  factory ContactInviteInviterPreview.fromJson(Map<String, dynamic> json) {
    return ContactInviteInviterPreview(
      userId: json['user_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
    );
  }
}

class ContactInvitePreview {
  final String status;
  final DateTime? expiresAt;
  final ContactInviteInviterPreview? inviter;

  ContactInvitePreview({required this.status, this.expiresAt, this.inviter});

  bool get canAttemptClaim => status == 'active' || status == 'used';

  factory ContactInvitePreview.fromJson(Map<String, dynamic> json) {
    final inviterJson = json['inviter'] as Map<String, dynamic>?;
    return ContactInvitePreview(
      status: json['status'] as String? ?? '',
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      inviter: inviterJson == null
          ? null
          : ContactInviteInviterPreview.fromJson(inviterJson),
    );
  }
}

class ContactInviteInviterClaim {
  final String userId;
  final String displayName;
  final String avatarUrl;
  final String matrixUserId;

  ContactInviteInviterClaim({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.matrixUserId,
  });

  factory ContactInviteInviterClaim.fromJson(Map<String, dynamic> json) {
    return ContactInviteInviterClaim(
      userId: json['user_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      matrixUserId: json['matrix_user_id'] as String? ?? '',
    );
  }
}

class ContactInviteClaimResult {
  final String status;
  final DateTime? expiresAt;
  final ContactInviteInviterClaim? inviter;

  ContactInviteClaimResult({
    required this.status,
    this.expiresAt,
    this.inviter,
  });

  factory ContactInviteClaimResult.fromJson(Map<String, dynamic> json) {
    final inviterJson = json['inviter'] as Map<String, dynamic>?;
    return ContactInviteClaimResult(
      status: json['status'] as String? ?? '',
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      inviter: inviterJson == null
          ? null
          : ContactInviteInviterClaim.fromJson(inviterJson),
    );
  }
}

class ContactInviteCompleteResult {
  final String status;
  final String acceptedRoomId;
  final DateTime? expiresAt;
  final DateTime? completedAt;

  ContactInviteCompleteResult({
    required this.status,
    required this.acceptedRoomId,
    this.expiresAt,
    this.completedAt,
  });

  factory ContactInviteCompleteResult.fromJson(Map<String, dynamic> json) {
    return ContactInviteCompleteResult(
      status: json['status'] as String? ?? '',
      acceptedRoomId: json['accepted_room_id'] as String? ?? '',
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
    );
  }
}

/// 单个协议的接受状态
class AgreementAcceptance {
  final int agreementId;
  final String type;
  final String version;
  final String url;
  final bool accepted;
  final DateTime? acceptedAt;

  AgreementAcceptance({
    required this.agreementId,
    required this.type,
    required this.version,
    required this.url,
    required this.accepted,
    this.acceptedAt,
  });

  factory AgreementAcceptance.fromJson(Map<String, dynamic> json) {
    return AgreementAcceptance(
      agreementId: json['agreement_id'] as int? ?? 0,
      type: json['type'] as String? ?? '',
      version: json['version'] as String? ?? '',
      url: json['url'] as String? ?? '',
      accepted: json['accepted'] as bool? ?? false,
      acceptedAt: json['accepted_at'] != null
          ? DateTime.tryParse(json['accepted_at'] as String)
          : null,
    );
  }
}
