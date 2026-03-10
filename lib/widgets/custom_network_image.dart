import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image/image.dart' as img;

import 'package:psygo/utils/custom_http_client.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/widgets/dicebear_avatar_fallback.dart';

/// 自定义网络图片组件
///
/// 使用 Image.network 加载图片，通过 HttpOverrides 处理证书问题
class CustomNetworkImage extends StatelessWidget {
  /// 清除所有图片缓存（退出登录时调用）
  static void clearCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const CustomNetworkImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.loadingBuilder,
    this.errorBuilder,
  });

  bool get _useDirectImageOnIos {
    return PlatformInfos.isIOS && _diceBearSpec != null;
  }

  DiceBearAvatarSpec? get _diceBearSpec => DiceBearAvatarSpec.tryParse(url);

  Widget _buildDiceBearFallback() {
    final spec = _diceBearSpec;
    if (spec == null) {
      return const SizedBox.shrink();
    }
    return DiceBearAvatarFallback(
      spec: spec,
      width: width,
      height: height,
    );
  }

  Widget _buildError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    debugPrint('[CustomNetworkImage] Failed to load image: $url');
    debugPrint('[CustomNetworkImage] Error: $error');
    if (_diceBearSpec != null) {
      return _buildDiceBearFallback();
    }
    if (errorBuilder != null) {
      return errorBuilder!(context, error, stackTrace);
    }
    return const SizedBox.shrink();
  }

  Widget? _buildDiceBearPlaceholder(BuildContext context) {
    if (_diceBearSpec == null) {
      return null;
    }
    final fallback = _buildDiceBearFallback();
    if (loadingBuilder == null) {
      return fallback;
    }
    return loadingBuilder!(context, fallback, null);
  }

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final memCacheWidth =
        width == null ? null : (width! * devicePixelRatio).round();
    final memCacheHeight =
        height == null ? null : (height! * devicePixelRatio).round();

    // DiceBear PNGs on iOS are fetched and re-encoded in Dart to avoid
    // native decoding/caching incompatibilities seen on some iOS builds.
    if (_useDirectImageOnIos) {
      return _IosReencodedNetworkImage(
        url,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: loadingBuilder,
        errorBuilder: _buildError,
        fallbackBuilder: (_) => _buildDiceBearFallback(),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      placeholder: (context, _) {
        final diceBearPlaceholder = _buildDiceBearPlaceholder(context);
        if (diceBearPlaceholder != null) {
          return diceBearPlaceholder;
        }
        if (loadingBuilder == null) {
          return const SizedBox.shrink();
        }
        return loadingBuilder!(
          context,
          const SizedBox.shrink(),
          const ImageChunkEvent(
            cumulativeBytesLoaded: 0,
            expectedTotalBytes: 1,
          ),
        );
      },
      imageBuilder: (context, imageProvider) {
        final image = Image(
          image: imageProvider,
          fit: fit,
          width: width,
          height: height,
        );
        if (loadingBuilder == null) {
          return image;
        }
        return loadingBuilder!(context, image, null);
      },
      errorWidget: (context, _, error) =>
          _buildError(context, error, StackTrace.current),
    );
  }
}

class _IosReencodedNetworkImage extends StatefulWidget {
  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;
  final Widget Function(BuildContext, Object, StackTrace?) errorBuilder;
  final Widget Function(BuildContext) fallbackBuilder;

  const _IosReencodedNetworkImage(
    this.url, {
    required this.errorBuilder,
    required this.fallbackBuilder,
    this.fit,
    this.width,
    this.height,
    this.loadingBuilder,
  });

  @override
  State<_IosReencodedNetworkImage> createState() =>
      _IosReencodedNetworkImageState();
}

class _IosReencodedNetworkImageState extends State<_IosReencodedNetworkImage> {
  static final Map<String, Uint8List> _memoryCache = {};

  late Future<Uint8List> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _loadImageBytes();
  }

  @override
  void didUpdateWidget(covariant _IosReencodedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _imageFuture = _loadImageBytes();
    }
  }

  Future<Uint8List> _loadImageBytes() async {
    final cached = _memoryCache[widget.url];
    if (cached != null) {
      return cached;
    }

    final client = CustomHttpClient.createHTTPClient();
    try {
      final uri = Uri.parse(widget.url);
      final response = await client.get(
        uri,
        headers: const {
          'Accept': 'image/png,image/*;q=0.8,*/*;q=0.5',
        },
      ).timeout(
        const Duration(seconds: 6),
        onTimeout: () => throw TimeoutException(
          'Timed out while loading $uri',
        ),
      );
      debugPrint(
        '[CustomNetworkImage] Fetch ${widget.url} -> ${response.statusCode}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final rawBytes = response.bodyBytes;
      final decoded = img.decodeImage(rawBytes);
      final normalized = decoded == null
          ? rawBytes
          : Uint8List.fromList(img.encodePng(decoded));
      _memoryCache[widget.url] = normalized;
      return normalized;
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder(
            context,
            snapshot.error!,
            snapshot.stackTrace,
          );
        }

        if (!snapshot.hasData) {
          final fallback = widget.fallbackBuilder(context);
          if (widget.loadingBuilder != null) {
            return widget.loadingBuilder!(
              context,
              fallback,
              null,
            );
          }
          return fallback;
        }

        final image = Image.memory(
          snapshot.data!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              widget.errorBuilder(context, error, stackTrace),
        );
        if (widget.loadingBuilder == null) {
          return image;
        }
        return widget.loadingBuilder!(context, image, null);
      },
    );
  }
}
