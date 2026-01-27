import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/retry.dart' as retry;

import 'package:psygo/config/isrg_x1.dart';
import 'package:psygo/utils/platform_infos.dart';

/// Custom Client to add an additional certificate. This is for the isrg X1
/// certificate which is needed for LetsEncrypt certificates. It is shipped
/// on Android since OS version 7.1. As long as we support older versions we
/// still have to ship this certificate by ourself.
///
/// Windows 10 older versions may also lack ISRG Root X1 certificate,
/// so we add it for Windows as well.
///
/// See: https://github.com/dart-lang/sdk/issues/52266
/// See: https://medium.com/@sherpya/lets-encrypt-and-flutter-after-september-30-2021-997b6605e396
class CustomHttpClient {
  /// 缓存的 SecurityContext，避免重复创建和添加证书
  static SecurityContext? _cachedContext;

  /// 创建带有 ISRG X1 证书的 SecurityContext
  /// 使用 withTrustedRoots: true 来包含系统信任的根证书
  static SecurityContext _getSecurityContext(String? cert) {
    if (_cachedContext != null) {
      return _cachedContext!;
    }

    // 创建新的 SecurityContext，包含系统信任的根证书
    // 这比 defaultContext 更可靠，因为 defaultContext 在 Windows 上
    // 使用 Mozilla 的证书列表，可能缺少某些根证书
    final context = SecurityContext(withTrustedRoots: true);

    if (cert != null) {
      try {
        final bytes = utf8.encode(cert);
        context.setTrustedCertificatesBytes(bytes);
        debugPrint('[CustomHttpClient] ISRG X1 certificate added successfully');
      } on TlsException catch (e) {
        if (e.osError != null &&
            e.osError!.message.contains('CERT_ALREADY_IN_HASH_TABLE')) {
          // Certificate already exists, ignore
          debugPrint('[CustomHttpClient] ISRG X1 certificate already exists');
        } else {
          debugPrint('[CustomHttpClient] Failed to add certificate: $e');
          // 不抛出异常，继续使用没有额外证书的 context
        }
      } catch (e) {
        debugPrint('[CustomHttpClient] Unexpected error adding certificate: $e');
      }
    }

    _cachedContext = context;
    return context;
  }

  static HttpClient customHttpClient(String? cert) {
    final context = _getSecurityContext(cert);
    return HttpClient(context: context);
  }

  /// 判断是否需要自定义证书处理
  /// Android 7.0 以下和 Windows 10 旧版本可能缺少 ISRG Root X1 证书
  static bool get _needsCustomCert {
    if (kIsWeb) return false;
    return PlatformInfos.isAndroid || PlatformInfos.isWindows;
  }

  static http.Client createHTTPClient() => retry.RetryClient(
        _needsCustomCert
            ? IOClient(customHttpClient(ISRG_X1))
            : http.Client(),
      );

  /// 使用自定义证书配置全局 HttpOverrides（供 Image.network 使用）
  static void applyHttpOverrides() {
    if (!_needsCustomCert) return;
    HttpOverrides.global = _CustomHttpOverrides();
  }

  /// 为 Dio 创建自定义 HttpClientAdapter，支持 ISRG X1 证书
  /// 用于解决 Windows 10 旧版本缺少 Let's Encrypt 根证书的问题
  static HttpClientAdapter createDioAdapter() {
    final adapter = IOHttpClientAdapter(
      createHttpClient: () {
        if (_needsCustomCert) {
          return customHttpClient(ISRG_X1);
        }
        return HttpClient();
      },
    );

    return adapter;
  }

  /// 创建配置好证书的 Dio 实例
  static Dio createDio() {
    final dio = Dio();

    // 非 Web 平台使用自定义 adapter
    if (!kIsWeb) {
      dio.httpClientAdapter = createDioAdapter();
    }

    return dio;
  }
}

class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    if (CustomHttpClient._needsCustomCert) {
      return CustomHttpClient.customHttpClient(ISRG_X1);
    }
    return super.createHttpClient(context);
  }
}
