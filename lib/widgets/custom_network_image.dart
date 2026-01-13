import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/custom_http_client.dart';

/// 自定义网络图片组件
///
/// 使用 CustomHttpClient（包含 ISRG X1 证书）加载图片，
/// 解决 Win10 上 Let's Encrypt SSL 证书验证失败的问题
class CustomNetworkImage extends StatefulWidget {
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

  @override
  State<CustomNetworkImage> createState() => _CustomNetworkImageState();
}

class _CustomNetworkImageState extends State<CustomNetworkImage> {
  Uint8List? _imageData;
  bool _isLoading = true;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CustomNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _imageData = null;
    });

    try {
      // 使用 CustomHttpClient 获取图片
      final httpClient = CustomHttpClient.createHTTPClient();
      try {
        final response = await httpClient.get(Uri.parse(widget.url));

        if (!mounted) return;

        if (response.statusCode == 200) {
          setState(() {
            _imageData = response.bodyBytes;
            _isLoading = false;
          });
        } else {
          throw Exception(
            'Failed to load image: ${response.statusCode}',
          );
        }
      } finally {
        httpClient.close();
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _stackTrace = stackTrace;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _error!, _stackTrace);
    }

    if (_error != null) {
      return const Icon(Icons.error_outline);
    }

    if (_imageData != null) {
      final image = Image.memory(
        _imageData!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
      );

      if (widget.loadingBuilder != null) {
        return widget.loadingBuilder!(context, image, null);
      }

      return image;
    }

    // Loading state
    if (widget.loadingBuilder != null) {
      return widget.loadingBuilder!(
        context,
        const SizedBox.shrink(),
        ImageChunkEvent(
          cumulativeBytesLoaded: 0,
          expectedTotalBytes: 1,
        ),
      );
    }

    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}
