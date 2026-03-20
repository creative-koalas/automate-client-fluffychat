import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';

import 'package:psygo/l10n/l10n.dart';

enum _DragHandle {
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

enum _EditorTool {
  crop,
  doodle,
  arrow,
  rect,
  text,
  mosaic,
}

final class _EditorStroke {
  _EditorStroke({
    required this.tool,
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  final _EditorTool tool;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
}

final class _EditorShape {
  _EditorShape({
    required this.tool,
    required this.start,
    required this.end,
    required this.color,
    required this.strokeWidth,
  });

  final _EditorTool tool;
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
}

final class _EditorText {
  _EditorText({
    required this.id,
    required this.text,
    required this.position,
    required this.color,
    required this.fontSize,
    required this.scale,
    required this.rotation,
  });

  final String id;
  final String text;
  final Offset position;
  final Color color;
  final double fontSize;
  final double scale;
  final double rotation;
}

Future<XFile?> showScreenshotCropperDialog(
  BuildContext context, {
  required XFile file,
}) {
  return showGeneralDialog<XFile>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'ScreenshotCropper',
    barrierColor: Colors.black.withValues(alpha: 0.08),
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (context, _, __) => _ScreenshotCropperDialog(file: file),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: child,
      );
    },
  );
}

class _ScreenshotCropperDialog extends StatefulWidget {
  final XFile file;

  const _ScreenshotCropperDialog({required this.file});

  @override
  State<_ScreenshotCropperDialog> createState() =>
      _ScreenshotCropperDialogState();
}

class _ScreenshotCropperDialogState extends State<_ScreenshotCropperDialog> {
  static const _minSelectionSize = 0.08;
  static const List<Color> _palette = [
    Color(0xFFFF4D4F),
    Color(0xFFFAAD14),
    Color(0xFF52C41A),
    Color(0xFF1890FF),
    Color(0xFFF759AB),
    Colors.white,
  ];

  final GlobalKey _imageBoundaryKey = GlobalKey();
  final TextEditingController _draftTextController = TextEditingController();
  final FocusNode _draftTextFocusNode = FocusNode();
  late Future<Uint8List> _bytesFuture;
  late Future<Uint8List> _pixelatedBytesFuture;

  Rect _selection = const Rect.fromLTWH(0.22, 0.18, 0.46, 0.34);
  _DragHandle? _activeHandle;
  Rect? _dragStartSelection;
  Offset? _dragStartPosition;

  _EditorTool _tool = _EditorTool.crop;
  Color _activeColor = _palette.first;
  String? _pendingText;
  bool _showMarkupToolbar = false;

  final List<_EditorStroke> _strokes = [];
  final List<_EditorShape> _shapes = [];
  final List<_EditorText> _texts = [];
  final List<_EditorAction> _history = [];
  int? _activeTextIndex;
  int? _editingTextIndex;
  int? _transformingTextIndex;
  Offset? _textTransformStartPosition;
  Offset? _textTransformStartFocalPoint;
  double? _textTransformStartScale;
  double? _textTransformStartRotation;
  Offset? _draftTextPosition;
  double _draftTextFontSize = 0.034;

  _EditorStroke? _draftStroke;
  _EditorShape? _draftShape;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _bytesFuture = widget.file.readAsBytes();
    _pixelatedBytesFuture = _bytesFuture.then(_buildPixelatedBytes);
  }

  @override
  void dispose() {
    _draftTextController.dispose();
    _draftTextFocusNode.dispose();
    super.dispose();
  }

  void _startCropDrag(_DragHandle handle, DragStartDetails details) {
    _activeHandle = handle;
    _dragStartSelection = _selection;
    _dragStartPosition = details.globalPosition;
  }

  void _updateCropDrag(Size imageSize, DragUpdateDetails details) {
    final handle = _activeHandle;
    final startSelection = _dragStartSelection;
    final startPosition = _dragStartPosition;
    if (handle == null || startSelection == null || startPosition == null) {
      return;
    }

    final dx = (details.globalPosition.dx - startPosition.dx) / imageSize.width;
    final dy =
        (details.globalPosition.dy - startPosition.dy) / imageSize.height;
    var next = startSelection;

    switch (handle) {
      case _DragHandle.move:
        final maxLeft = 1.0 - startSelection.width;
        final maxTop = 1.0 - startSelection.height;
        next = Rect.fromLTWH(
          (startSelection.left + dx).clamp(0.0, maxLeft),
          (startSelection.top + dy).clamp(0.0, maxTop),
          startSelection.width,
          startSelection.height,
        );
        break;
      case _DragHandle.topLeft:
        final newLeft = (startSelection.left + dx)
            .clamp(0.0, startSelection.right - _minSelectionSize);
        final newTop = (startSelection.top + dy)
            .clamp(0.0, startSelection.bottom - _minSelectionSize);
        next = Rect.fromLTRB(
          newLeft,
          newTop,
          startSelection.right,
          startSelection.bottom,
        );
        break;
      case _DragHandle.topRight:
        final newRight = (startSelection.right + dx)
            .clamp(startSelection.left + _minSelectionSize, 1.0);
        final newTop = (startSelection.top + dy)
            .clamp(0.0, startSelection.bottom - _minSelectionSize);
        next = Rect.fromLTRB(
          startSelection.left,
          newTop,
          newRight,
          startSelection.bottom,
        );
        break;
      case _DragHandle.bottomLeft:
        final newLeft = (startSelection.left + dx)
            .clamp(0.0, startSelection.right - _minSelectionSize);
        final newBottom = (startSelection.bottom + dy)
            .clamp(startSelection.top + _minSelectionSize, 1.0);
        next = Rect.fromLTRB(
          newLeft,
          startSelection.top,
          startSelection.right,
          newBottom,
        );
        break;
      case _DragHandle.bottomRight:
        final newRight = (startSelection.right + dx)
            .clamp(startSelection.left + _minSelectionSize, 1.0);
        final newBottom = (startSelection.bottom + dy)
            .clamp(startSelection.top + _minSelectionSize, 1.0);
        next = Rect.fromLTRB(
          startSelection.left,
          startSelection.top,
          newRight,
          newBottom,
        );
        break;
    }

    setState(() => _selection = next);
  }

  void _endCropDrag(DragEndDetails _) {
    _activeHandle = null;
    _dragStartSelection = null;
    _dragStartPosition = null;
  }

  void _startStroke(Offset position) {
    final stroke = _EditorStroke(
      tool: _tool,
      points: [position],
      color: _tool == _EditorTool.mosaic ? Colors.transparent : _activeColor,
      strokeWidth: _tool == _EditorTool.mosaic ? 0.05 : 0.009,
    );
    setState(() => _draftStroke = stroke);
  }

  void _updateStroke(Offset position) {
    final draft = _draftStroke;
    if (draft == null) return;
    setState(() {
      _draftStroke = _EditorStroke(
        tool: draft.tool,
        points: [...draft.points, position],
        color: draft.color,
        strokeWidth: draft.strokeWidth,
      );
    });
  }

  void _finishStroke() {
    final draft = _draftStroke;
    if (draft == null) return;
    if (draft.points.length > 1) {
      setState(() {
        _strokes.add(draft);
        _history.add(_EditorAction.stroke(draft));
        _draftStroke = null;
      });
      return;
    }
    setState(() => _draftStroke = null);
  }

  void _startShape(Offset position) {
    setState(() {
      _draftShape = _EditorShape(
        tool: _tool,
        start: position,
        end: position,
        color: _activeColor,
        strokeWidth: 0.008,
      );
    });
  }

  void _updateShape(Offset position) {
    final draft = _draftShape;
    if (draft == null) return;
    setState(() {
      _draftShape = _EditorShape(
        tool: draft.tool,
        start: draft.start,
        end: position,
        color: draft.color,
        strokeWidth: draft.strokeWidth,
      );
    });
  }

  void _finishShape() {
    final draft = _draftShape;
    if (draft == null) return;
    final delta = (draft.end - draft.start).distance;
    if (delta > 0.01) {
      setState(() {
        _shapes.add(draft);
        _history.add(_EditorAction.shape(draft));
        _draftShape = null;
      });
      return;
    }
    setState(() => _draftShape = null);
  }

  Future<void> _placeText(Offset position) async {
    setState(() {
      _draftTextPosition = position;
      _draftTextFontSize =
          _activeTextIndex != null ? _texts[_activeTextIndex!].fontSize : 0.034;
      _editingTextIndex = null;
      _activeTextIndex = null;
      _draftTextController.text = _pendingText ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _draftTextFocusNode.requestFocus();
        _draftTextController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _draftTextController.text.length,
        );
      }
    });
  }

  void _startTextTransform(int index, Offset focalPoint) {
    if (index < 0 || index >= _texts.length) return;
    final item = _texts[index];
    setState(() {
      _activeTextIndex = index;
      _transformingTextIndex = index;
      _textTransformStartPosition = item.position;
      _textTransformStartFocalPoint = focalPoint;
      _textTransformStartScale = item.scale;
      _textTransformStartRotation = item.rotation;
    });
  }

  void _updateTextTransform(
    int index, {
    required Offset focalPoint,
    required Size canvasSize,
    required double scale,
    required double rotation,
  }) {
    if (index < 0 || index >= _texts.length) return;
    if (_transformingTextIndex != index ||
        _textTransformStartPosition == null ||
        _textTransformStartFocalPoint == null ||
        _textTransformStartScale == null ||
        _textTransformStartRotation == null) {
      return;
    }

    final moveDelta = Offset(
      (focalPoint.dx - _textTransformStartFocalPoint!.dx) / canvasSize.width,
      (focalPoint.dy - _textTransformStartFocalPoint!.dy) / canvasSize.height,
    );

    final item = _texts[index];
    final nextPosition = Offset(
      (_textTransformStartPosition!.dx + moveDelta.dx).clamp(0.0, 0.94),
      (_textTransformStartPosition!.dy + moveDelta.dy).clamp(0.0, 0.96),
    );
    final nextScale = (_textTransformStartScale! * scale).clamp(0.6, 3.2);
    final nextRotation = _textTransformStartRotation! + rotation;

    setState(() {
      _texts[index] = _EditorText(
        id: item.id,
        text: item.text,
        position: nextPosition,
        color: item.color,
        fontSize: item.fontSize,
        scale: nextScale,
        rotation: nextRotation,
      );
    });
  }

  void _endTextTransform() {
    _transformingTextIndex = null;
    _textTransformStartPosition = null;
    _textTransformStartFocalPoint = null;
    _textTransformStartScale = null;
    _textTransformStartRotation = null;
  }

  void _selectText(int index) {
    if (index < 0 || index >= _texts.length) return;
    setState(() {
      _activeTextIndex = index;
      _draftTextPosition = null;
      _editingTextIndex = null;
    });
  }

  Future<void> _editText(int index) async {
    if (index < 0 || index >= _texts.length) return;
    final item = _texts[index];
    setState(() {
      _editingTextIndex = index;
      _activeTextIndex = index;
      _draftTextPosition = item.position;
      _draftTextFontSize = item.fontSize;
      _activeColor = item.color;
      _draftTextController.text = item.text;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _draftTextFocusNode.requestFocus();
        _draftTextController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _draftTextController.text.length,
        );
      }
    });
  }

  Future<void> _openMarkupTool(_EditorTool tool) async {
    if (!mounted) return;
    setState(() {
      _tool = tool;
      _showMarkupToolbar = tool != _EditorTool.crop;
    });
  }

  void _cancelDraftText() {
    setState(() {
      _draftTextPosition = null;
      _editingTextIndex = null;
      _draftTextController.clear();
    });
  }

  void _commitDraftText() {
    final text = _draftTextController.text.trim();
    final position = _draftTextPosition;
    if (position == null) return;
    _draftTextFocusNode.unfocus();
    if (text.isEmpty) {
      _cancelDraftText();
      return;
    }

    final existingIndex = _editingTextIndex;
    if (existingIndex != null &&
        existingIndex >= 0 &&
        existingIndex < _texts.length) {
      final current = _texts[existingIndex];
      setState(() {
        _texts[existingIndex] = _EditorText(
          id: current.id,
          text: text,
          position: current.position,
          color: _activeColor,
          fontSize: _draftTextFontSize,
          scale: current.scale,
          rotation: current.rotation,
        );
        _pendingText = text;
        _draftTextPosition = null;
        _editingTextIndex = null;
        _activeTextIndex = existingIndex;
      });
      return;
    }

    final item = _EditorText(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      position: position,
      color: _activeColor,
      fontSize: _draftTextFontSize,
      scale: 1,
      rotation: 0,
    );
    setState(() {
      _texts.add(item);
      _history.add(_EditorAction.text(item));
      _pendingText = text;
      _draftTextPosition = null;
      _editingTextIndex = null;
      _activeTextIndex = _texts.length - 1;
    });
  }

  void _applyTextColor(Color color) {
    setState(() {
      _activeColor = color;
      final draftIndex = _editingTextIndex;
      if (draftIndex != null &&
          draftIndex >= 0 &&
          draftIndex < _texts.length &&
          _draftTextPosition != null) {
        final item = _texts[draftIndex];
        _texts[draftIndex] = _EditorText(
          id: item.id,
          text: item.text,
          position: item.position,
          color: color,
          fontSize: item.fontSize,
          scale: item.scale,
          rotation: item.rotation,
        );
      } else if (_activeTextIndex != null &&
          _activeTextIndex! >= 0 &&
          _activeTextIndex! < _texts.length) {
        final item = _texts[_activeTextIndex!];
        _texts[_activeTextIndex!] = _EditorText(
          id: item.id,
          text: item.text,
          position: item.position,
          color: color,
          fontSize: item.fontSize,
          scale: item.scale,
          rotation: item.rotation,
        );
      }
    });
  }

  void _adjustTextFontSize(double delta) {
    setState(() {
      _draftTextFontSize = (_draftTextFontSize + delta).clamp(0.02, 0.09);
      final activeIndex = _activeTextIndex;
      if (_draftTextPosition == null &&
          activeIndex != null &&
          activeIndex >= 0 &&
          activeIndex < _texts.length) {
        final item = _texts[activeIndex];
        _texts[activeIndex] = _EditorText(
          id: item.id,
          text: item.text,
          position: item.position,
          color: item.color,
          fontSize: (_texts[activeIndex].fontSize + delta).clamp(0.02, 0.09),
          scale: item.scale,
          rotation: item.rotation,
        );
      }
    });
  }

  Uint8List _buildPixelatedBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final downscaled = img.copyResize(
      decoded,
      width: math.max((decoded.width / 14).round(), 64),
      height: math.max((decoded.height / 14).round(), 64),
      interpolation: img.Interpolation.nearest,
    );
    final upscaled = img.copyResize(
      downscaled,
      width: decoded.width,
      height: decoded.height,
      interpolation: img.Interpolation.nearest,
    );
    return Uint8List.fromList(img.encodePng(upscaled));
  }

  void _undo() {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    setState(() {
      switch (last.type) {
        case _EditorActionType.stroke:
          _strokes.remove(last.stroke);
          break;
        case _EditorActionType.shape:
          _shapes.remove(last.shape);
          break;
        case _EditorActionType.text:
          final removedId = last.text?.id;
          _texts.removeWhere((item) => item.id == removedId);
          if (_activeTextIndex != null && _activeTextIndex! >= _texts.length) {
            _activeTextIndex = _texts.isEmpty ? null : _texts.length - 1;
          }
          break;
      }
    });
  }

  Future<void> _confirmImage(Uint8List bytes, Size rawSize) async {
    if (_submitting) return;
    final boundaryContext = _imageBoundaryKey.currentContext;
    if (boundaryContext == null) return;
    final renderObject = boundaryContext.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return;

    setState(() => _submitting = true);
    try {
      final box = boundaryContext.findRenderObject() as RenderBox;
      final pixelRatio = rawSize.width / box.size.width;
      final renderedImage = await renderObject.toImage(pixelRatio: pixelRatio);
      final byteData =
          await renderedImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      final composed = img.decodeImage(byteData.buffer.asUint8List());
      if (composed == null) {
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      final cropX = (_selection.left * composed.width)
          .round()
          .clamp(0, composed.width - 1);
      final cropY = (_selection.top * composed.height)
          .round()
          .clamp(0, composed.height - 1);
      final cropWidth = (_selection.width * composed.width)
          .round()
          .clamp(1, composed.width - cropX);
      final cropHeight = (_selection.height * composed.height)
          .round()
          .clamp(1, composed.height - cropY);

      final outputImage = img.copyCrop(
        composed,
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
      );

      final tempDir = await getTemporaryDirectory();
      final outputPath = path_lib.join(
        tempDir.path,
        'psygo_screenshot_edit_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodePng(outputImage), flush: true);

      if (!mounted) return;
      Navigator.of(context).pop(
        XFile(
          outputFile.path,
          name: path_lib.basename(outputFile.path),
          mimeType: 'image/png',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _toolLabel(BuildContext context, _EditorTool tool) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    return switch (tool) {
      _EditorTool.crop => isZh ? '裁剪' : 'Crop',
      _EditorTool.doodle => isZh ? '涂鸦' : 'Draw',
      _EditorTool.arrow => isZh ? '箭头' : 'Arrow',
      _EditorTool.rect => isZh ? '矩形' : 'Rect',
      _EditorTool.text => isZh ? '文字' : 'Text',
      _EditorTool.mosaic => isZh ? '马赛克' : 'Mosaic',
    };
  }

  String _hintLabel(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    return switch (_tool) {
      _EditorTool.crop => isZh
          ? '拖动顶部拖拽条移动，拖动四角调整大小'
          : 'Drag the top handle to move and corners to resize',
      _EditorTool.doodle => isZh ? '按住拖动进行涂鸦' : 'Drag to doodle',
      _EditorTool.arrow => isZh ? '拖动添加箭头标注' : 'Drag to place an arrow',
      _EditorTool.rect => isZh ? '拖动添加矩形标注' : 'Drag to place a rectangle',
      _EditorTool.text => isZh ? '点击图片放置文字，首次会先输入内容' : 'Tap to place text',
      _EditorTool.mosaic => isZh ? '按住拖动涂抹马赛克' : 'Drag to paint mosaic',
    };
  }

  IconData _toolIcon(_EditorTool tool) {
    return switch (tool) {
      _EditorTool.crop => Icons.crop_free_rounded,
      _EditorTool.doodle => Icons.edit_rounded,
      _EditorTool.arrow => Icons.north_east_rounded,
      _EditorTool.rect => Icons.rectangle_outlined,
      _EditorTool.text => Icons.text_fields_rounded,
      _EditorTool.mosaic => Icons.blur_on_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Material(
      color: Colors.black,
      child: FutureBuilder<Uint8List>(
        future: _bytesFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }
          return FutureBuilder<ImageInfo>(
            future: _resolveImage(MemoryImage(bytes)),
            builder: (context, imageSnapshot) {
              final imageInfo = imageSnapshot.data;
              if (imageInfo == null) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }
              final rawSize = Size(
                imageInfo.image.width.toDouble(),
                imageInfo.image.height.toDouble(),
              );
              return LayoutBuilder(
                builder: (context, constraints) {
                  final imageRect = Offset.zero & constraints.biggest;
                  final selectionRect = Rect.fromLTWH(
                    imageRect.left + _selection.left * imageRect.width,
                    imageRect.top + _selection.top * imageRect.height,
                    _selection.width * imageRect.width,
                    _selection.height * imageRect.height,
                  );
                  const overlayGap = 12.0;
                  const actionsWidth = 206.0;
                  const actionsHeight = 44.0;
                  const toolbarHeight = 58.0;
                  const toolbarMinWidth = 420.0;
                  final topSpace = selectionRect.top - imageRect.top;
                  final bottomSpace = imageRect.bottom - selectionRect.bottom;
                  final leftSpace = selectionRect.left - imageRect.left;
                  final rightSpace = imageRect.right - selectionRect.right;
                  final isNearFullscreen =
                      selectionRect.width >= imageRect.width * 0.66 ||
                          selectionRect.height >= imageRect.height * 0.58;
                  final actionFitsAbove =
                      topSpace >= actionsHeight + overlayGap;
                  final actionFitsBelow =
                      bottomSpace >= actionsHeight + overlayGap;
                  final canDockActionsToSelection = !isNearFullscreen &&
                      (selectionRect.width >= actionsWidth ||
                          actionFitsAbove ||
                          actionFitsBelow ||
                          rightSpace >= actionsWidth ||
                          leftSpace >= actionsWidth);

                  double actionsLeft;
                  double actionsTop;
                  if (isNearFullscreen) {
                    actionsLeft = (imageRect.right - actionsWidth - 18).clamp(
                      imageRect.left + 18,
                      imageRect.right - actionsWidth,
                    );
                    actionsTop = imageRect.top + 18;
                  } else if (canDockActionsToSelection) {
                    actionsLeft = selectionRect.right - actionsWidth;
                    if (actionsLeft < imageRect.left) {
                      actionsLeft = selectionRect.left;
                    }
                    actionsLeft = actionsLeft.clamp(
                      imageRect.left,
                      imageRect.right - actionsWidth,
                    );
                    if (actionFitsAbove) {
                      actionsTop =
                          selectionRect.top - actionsHeight - overlayGap;
                    } else if (actionFitsBelow) {
                      actionsTop = selectionRect.bottom + overlayGap;
                    } else if (rightSpace >= actionsWidth) {
                      actionsLeft = selectionRect.right + overlayGap;
                      actionsTop = (selectionRect.top +
                              selectionRect.height / 2 -
                              actionsHeight / 2)
                          .clamp(
                        imageRect.top,
                        imageRect.bottom - actionsHeight,
                      );
                    } else {
                      actionsLeft =
                          selectionRect.left - actionsWidth - overlayGap;
                      actionsTop = (selectionRect.top +
                              selectionRect.height / 2 -
                              actionsHeight / 2)
                          .clamp(
                        imageRect.top,
                        imageRect.bottom - actionsHeight,
                      );
                    }
                  } else {
                    actionsLeft =
                        (imageRect.left + (imageRect.width - actionsWidth) / 2)
                            .clamp(
                      imageRect.left,
                      imageRect.right - actionsWidth,
                    );
                    actionsTop = imageRect.bottom - actionsHeight - 18;
                  }

                  final toolbarWidth = math.min(
                    math.max(selectionRect.width, toolbarMinWidth),
                    imageRect.width - 24,
                  );
                  final toolbarFitsBelow = bottomSpace >= toolbarHeight + 22;
                  final toolbarFitsAbove =
                      topSpace >= toolbarHeight + actionsHeight + 28;
                  final useBottomToolbar = isNearFullscreen ||
                      selectionRect.width >= imageRect.width * 0.5 ||
                      selectionRect.height >= imageRect.height * 0.36 ||
                      selectionRect.width < toolbarMinWidth * 0.8 ||
                      (!toolbarFitsBelow && !toolbarFitsAbove);
                  final toolbarLeft = useBottomToolbar
                      ? (imageRect.left + (imageRect.width - toolbarWidth) / 2)
                          .clamp(
                          imageRect.left + 12,
                          imageRect.right - toolbarWidth - 12,
                        )
                      : (selectionRect.left +
                              (selectionRect.width - toolbarWidth) / 2)
                          .clamp(
                          imageRect.left + 12,
                          imageRect.right - toolbarWidth - 12,
                        );
                  final toolbarTop = useBottomToolbar
                      ? imageRect.bottom - toolbarHeight - 18
                      : toolbarFitsBelow
                          ? selectionRect.bottom + overlayGap
                          : selectionRect.top - toolbarHeight - overlayGap;

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(0xFF050505),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: imageRect,
                        child: _EditorCanvas(
                          imageBoundaryKey: _imageBoundaryKey,
                          bytes: bytes,
                          pixelatedBytesFuture: _pixelatedBytesFuture,
                          selection: _selection,
                          tool: _tool,
                          strokes: _strokes,
                          draftStroke: _draftStroke,
                          shapes: _shapes,
                          draftShape: _draftShape,
                          texts: _texts,
                          draftTextPosition: _draftTextPosition,
                          editingTextIndex: _editingTextIndex,
                          draftTextController: _draftTextController,
                          draftTextFocusNode: _draftTextFocusNode,
                          draftTextColor: _activeColor,
                          draftTextFontSize: _draftTextFontSize,
                          onSubmitDraftText: _commitDraftText,
                          onCancelDraftText: _cancelDraftText,
                          onCropStartDrag: _startCropDrag,
                          onCropUpdateDrag: (details) => _updateCropDrag(
                            imageRect.size,
                            details,
                          ),
                          onCropEndDrag: _endCropDrag,
                          onStartStroke: _startStroke,
                          onUpdateStroke: _updateStroke,
                          onEndStroke: _finishStroke,
                          onStartShape: _startShape,
                          onUpdateShape: _updateShape,
                          onEndShape: _finishShape,
                          onTextTap: _placeText,
                          activeTextIndex: _activeTextIndex,
                          onSelectText: _selectText,
                          onStartTextTransform: _startTextTransform,
                          onUpdateTextTransform: _updateTextTransform,
                          onEndTextTransform: _endTextTransform,
                          onEditText: _editText,
                        ),
                      ),
                      Positioned(
                        left: imageRect.left + 18,
                        top: imageRect.top + 18,
                        child: _HintChip(
                          label: _hintLabel(context),
                        ),
                      ),
                      Positioned(
                        left: actionsLeft,
                        top: actionsTop,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RoundActionButton(
                              icon: Icons.brush_rounded,
                              enabled: !_submitting,
                              tooltip: Localizations.localeOf(context)
                                      .languageCode
                                      .startsWith('zh')
                                  ? '标注'
                                  : 'Markup',
                              active: _showMarkupToolbar,
                              onTap: () {
                                setState(() {
                                  _showMarkupToolbar = !_showMarkupToolbar;
                                  if (_showMarkupToolbar) {
                                    _tool = _EditorTool.doodle;
                                  } else {
                                    _tool = _EditorTool.crop;
                                  }
                                });
                              },
                            ),
                            const SizedBox(width: 10),
                            _RoundActionButton(
                              icon: Icons.undo_rounded,
                              enabled: _history.isNotEmpty && !_submitting,
                              tooltip: Localizations.localeOf(context)
                                      .languageCode
                                      .startsWith('zh')
                                  ? '撤销'
                                  : 'Undo',
                              onTap: _undo,
                            ),
                            const SizedBox(width: 10),
                            _RoundActionButton(
                              icon: Icons.close_rounded,
                              enabled: !_submitting,
                              tooltip: l10n.cancel,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: 10),
                            _RoundActionButton(
                              icon: Icons.check_rounded,
                              enabled: !_submitting,
                              tooltip: l10n.confirm,
                              filled: true,
                              busy: _submitting,
                              onTap: () => _confirmImage(bytes, rawSize),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: toolbarLeft,
                        width: toolbarWidth,
                        top: toolbarTop,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _showMarkupToolbar
                              ? _FloatingToolbar(
                                  key: const ValueKey('markup-toolbar'),
                                  tool: _tool,
                                  onToolSelected: _openMarkupTool,
                                  toolLabelBuilder: (tool) =>
                                      _toolLabel(context, tool),
                                  toolIconBuilder: _toolIcon,
                                  colors: _palette,
                                  activeColor: _activeColor,
                                  onColorSelected: _applyTextColor,
                                  showColors: _tool != _EditorTool.mosaic,
                                  canUndo: _history.isNotEmpty,
                                  textMode: _tool == _EditorTool.text,
                                  onIncreaseTextSize: () =>
                                      _adjustTextFontSize(0.004),
                                  onDecreaseTextSize: () =>
                                      _adjustTextFontSize(-0.004),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<ImageInfo> _resolveImage(ImageProvider provider) {
    final completer = Completer<ImageInfo>();
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info);
        stream.removeListener(listener);
      },
      onError: (error, _) {
        completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}

class _EditorCanvas extends StatelessWidget {
  const _EditorCanvas({
    required this.imageBoundaryKey,
    required this.bytes,
    required this.pixelatedBytesFuture,
    required this.selection,
    required this.tool,
    required this.strokes,
    required this.draftStroke,
    required this.shapes,
    required this.draftShape,
    required this.texts,
    required this.draftTextPosition,
    required this.editingTextIndex,
    required this.draftTextController,
    required this.draftTextFocusNode,
    required this.draftTextColor,
    required this.draftTextFontSize,
    required this.onSubmitDraftText,
    required this.onCancelDraftText,
    required this.onCropStartDrag,
    required this.onCropUpdateDrag,
    required this.onCropEndDrag,
    required this.onStartStroke,
    required this.onUpdateStroke,
    required this.onEndStroke,
    required this.onStartShape,
    required this.onUpdateShape,
    required this.onEndShape,
    required this.onTextTap,
    required this.activeTextIndex,
    required this.onSelectText,
    required this.onStartTextTransform,
    required this.onUpdateTextTransform,
    required this.onEndTextTransform,
    required this.onEditText,
  });

  final GlobalKey imageBoundaryKey;
  final Uint8List bytes;
  final Future<Uint8List> pixelatedBytesFuture;
  final Rect selection;
  final _EditorTool tool;
  final List<_EditorStroke> strokes;
  final _EditorStroke? draftStroke;
  final List<_EditorShape> shapes;
  final _EditorShape? draftShape;
  final List<_EditorText> texts;
  final Offset? draftTextPosition;
  final int? editingTextIndex;
  final TextEditingController draftTextController;
  final FocusNode draftTextFocusNode;
  final Color draftTextColor;
  final double draftTextFontSize;
  final VoidCallback onSubmitDraftText;
  final VoidCallback onCancelDraftText;
  final void Function(_DragHandle handle, DragStartDetails details)
      onCropStartDrag;
  final void Function(DragUpdateDetails details) onCropUpdateDrag;
  final void Function(DragEndDetails details) onCropEndDrag;
  final void Function(Offset position) onStartStroke;
  final void Function(Offset position) onUpdateStroke;
  final VoidCallback onEndStroke;
  final void Function(Offset position) onStartShape;
  final void Function(Offset position) onUpdateShape;
  final VoidCallback onEndShape;
  final Future<void> Function(Offset position) onTextTap;
  final int? activeTextIndex;
  final void Function(int index) onSelectText;
  final void Function(int index, Offset focalPoint) onStartTextTransform;
  final void Function(
    int index, {
    required Offset focalPoint,
    required Size canvasSize,
    required double scale,
    required double rotation,
  }) onUpdateTextTransform;
  final VoidCallback onEndTextTransform;
  final Future<void> Function(int index) onEditText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final selectionRect = Rect.fromLTWH(
          selection.left * size.width,
          selection.top * size.height,
          selection.width * size.width,
          selection.height * size.height,
        );

        Widget content = Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              key: imageBoundaryKey,
              child: SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.fill,
                      ),
                    ),
                    if (_mosaicStrokes(strokes, draftStroke).isNotEmpty)
                      Positioned.fill(
                        child: FutureBuilder<Uint8List>(
                          future: pixelatedBytesFuture,
                          builder: (context, snapshot) {
                            final pixelatedBytes = snapshot.data;
                            if (pixelatedBytes == null) {
                              return const SizedBox.shrink();
                            }
                            return ClipPath(
                              clipper: _MosaicClipper(
                                strokes: _mosaicStrokes(strokes, draftStroke),
                              ),
                              child: Image.memory(
                                pixelatedBytes,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.none,
                              ),
                            );
                          },
                        ),
                      ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _MarkupPainter(
                            strokes: strokes,
                            draftStroke: draftStroke,
                            shapes: shapes,
                            draftShape: draftShape,
                            texts: texts,
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < texts.length; i++)
                      if (editingTextIndex != i)
                        Positioned(
                          left: texts[i].position.dx * size.width,
                          top: texts[i].position.dy * size.height,
                          child: _RenderedTextLabel(
                            text: texts[i],
                            canvasWidth: size.width,
                          ),
                        ),
                  ],
                ),
              ),
            ),
            for (var i = 0; i < texts.length; i++)
              if (editingTextIndex != i)
                Positioned(
                  left: texts[i].position.dx * size.width,
                  top: texts[i].position.dy * size.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap:
                        tool == _EditorTool.text ? () => onSelectText(i) : null,
                    onScaleStart: tool == _EditorTool.text
                        ? (details) =>
                            onStartTextTransform(i, details.focalPoint)
                        : null,
                    onScaleUpdate: tool == _EditorTool.text
                        ? (details) => onUpdateTextTransform(
                              i,
                              focalPoint: details.focalPoint,
                              canvasSize: size,
                              scale: details.scale,
                              rotation: details.rotation,
                            )
                        : null,
                    onScaleEnd: tool == _EditorTool.text
                        ? (_) => onEndTextTransform()
                        : null,
                    onDoubleTap:
                        tool == _EditorTool.text ? () => onEditText(i) : null,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color:
                              tool == _EditorTool.text && activeTextIndex == i
                                  ? const Color(0xFF34D399)
                                  : Colors.transparent,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Opacity(
                        opacity: 0,
                        child: _RenderedTextLabel(
                          text: texts[i],
                          canvasWidth: size.width,
                        ),
                      ),
                    ),
                  ),
                ),
            if (draftTextPosition != null)
              Positioned(
                left: draftTextPosition!.dx * size.width,
                top: draftTextPosition!.dy * size.height,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(selectionRect.width * 0.8, 320),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.52),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF34D399)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: draftTextController,
                            focusNode: draftTextFocusNode,
                            autofocus: true,
                            minLines: 1,
                            maxLines: 4,
                            style: TextStyle(
                              color: draftTextColor,
                              fontSize: draftTextFontSize * size.width,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: Localizations.localeOf(context)
                                      .languageCode
                                      .startsWith('zh')
                                  ? '输入文字'
                                  : 'Type here',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                            onSubmitted: (_) => onSubmitDraftText(),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _InlineTextAction(
                                icon: Icons.close_rounded,
                                onTap: onCancelDraftText,
                              ),
                              const SizedBox(width: 8),
                              _InlineTextAction(
                                icon: Icons.check_rounded,
                                onTap: onSubmitDraftText,
                                highlighted: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CropMaskPainter(selectionRect: selectionRect),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: selectionRect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: const Color(0xFF34D399), width: 2),
                  ),
                ),
              ),
            ),
            Positioned(
              left: selectionRect.left,
              top: selectionRect.top - 14,
              width: selectionRect.width,
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (details) =>
                      onCropStartDrag(_DragHandle.move, details),
                  onPanUpdate: onCropUpdateDrag,
                  onPanEnd: onCropEndDrag,
                  child: Container(
                    width: math.min(selectionRect.width, 120),
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34D399),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 28,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _CropHandle(
              center: selectionRect.topLeft,
              onStartDrag: (details) =>
                  onCropStartDrag(_DragHandle.topLeft, details),
              onUpdateDrag: onCropUpdateDrag,
              onEndDrag: onCropEndDrag,
            ),
            _CropHandle(
              center: selectionRect.topRight,
              onStartDrag: (details) =>
                  onCropStartDrag(_DragHandle.topRight, details),
              onUpdateDrag: onCropUpdateDrag,
              onEndDrag: onCropEndDrag,
            ),
            _CropHandle(
              center: selectionRect.bottomLeft,
              onStartDrag: (details) =>
                  onCropStartDrag(_DragHandle.bottomLeft, details),
              onUpdateDrag: onCropUpdateDrag,
              onEndDrag: onCropEndDrag,
            ),
            _CropHandle(
              center: selectionRect.bottomRight,
              onStartDrag: (details) =>
                  onCropStartDrag(_DragHandle.bottomRight, details),
              onUpdateDrag: onCropUpdateDrag,
              onEndDrag: onCropEndDrag,
            ),
          ],
        );

        if (tool == _EditorTool.doodle || tool == _EditorTool.mosaic) {
          content = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              if (!_isInsideSelection(details.localPosition, selectionRect)) {
                return;
              }
              onStartStroke(_normalize(details.localPosition, size));
            },
            onPanUpdate: (details) {
              if (!_isInsideSelection(details.localPosition, selectionRect)) {
                return;
              }
              onUpdateStroke(_normalize(details.localPosition, size));
            },
            onPanEnd: (_) => onEndStroke(),
            child: content,
          );
        } else if (tool == _EditorTool.arrow || tool == _EditorTool.rect) {
          content = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              if (!_isInsideSelection(details.localPosition, selectionRect)) {
                return;
              }
              onStartShape(_normalize(details.localPosition, size));
            },
            onPanUpdate: (details) {
              if (!_isInsideSelection(details.localPosition, selectionRect)) {
                return;
              }
              onUpdateShape(_normalize(details.localPosition, size));
            },
            onPanEnd: (_) => onEndShape(),
            child: content,
          );
        } else if (tool == _EditorTool.text) {
          content = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              if (draftTextPosition != null) {
                return;
              }
              if (!_isInsideSelection(details.localPosition, selectionRect)) {
                return;
              }
              onTextTap(_normalize(details.localPosition, size));
            },
            child: content,
          );
        }

        return content;
      },
    );
  }

  List<_EditorStroke> _mosaicStrokes(
    List<_EditorStroke> items,
    _EditorStroke? draft,
  ) {
    final result = <_EditorStroke>[
      ...items.where((item) => item.tool == _EditorTool.mosaic),
    ];
    if (draft != null && draft.tool == _EditorTool.mosaic) {
      result.add(draft);
    }
    return result;
  }

  Offset _normalize(Offset position, Size size) {
    return Offset(
      (position.dx / size.width).clamp(0.0, 1.0),
      (position.dy / size.height).clamp(0.0, 1.0),
    );
  }

  bool _isInsideSelection(Offset position, Rect selectionRect) {
    return selectionRect.contains(position);
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
    this.busy = false,
    this.active = false,
  });

  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;
  final bool filled;
  final bool busy;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled
            ? const Color(0xFF34D399)
            : active
                ? const Color(0xFF3B404B)
                : Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: filled ? Colors.black : Colors.white,
                      ),
                    )
                  : Icon(
                      icon,
                      color: enabled
                          ? (filled
                              ? Colors.black
                              : active
                                  ? const Color(0xFF34D399)
                                  : Colors.white)
                          : Colors.white.withValues(alpha: 0.45),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingToolbar extends StatelessWidget {
  const _FloatingToolbar({
    super.key,
    required this.tool,
    required this.onToolSelected,
    required this.toolLabelBuilder,
    required this.toolIconBuilder,
    required this.colors,
    required this.activeColor,
    required this.onColorSelected,
    required this.showColors,
    required this.canUndo,
    required this.textMode,
    required this.onIncreaseTextSize,
    required this.onDecreaseTextSize,
  });

  final _EditorTool tool;
  final ValueChanged<_EditorTool> onToolSelected;
  final String Function(_EditorTool tool) toolLabelBuilder;
  final IconData Function(_EditorTool tool) toolIconBuilder;
  final List<Color> colors;
  final Color activeColor;
  final ValueChanged<Color> onColorSelected;
  final bool showColors;
  final bool canUndo;
  final bool textMode;
  final VoidCallback onIncreaseTextSize;
  final VoidCallback onDecreaseTextSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC1A1D24),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in _EditorTool.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _ToolButton(
                      icon: toolIconBuilder(item),
                      label: toolLabelBuilder(item),
                      selected: tool == item,
                      onTap: () => onToolSelected(item),
                    ),
                  ),
                if (textMode) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    height: 28,
                    color: Colors.white.withValues(alpha: 0.09),
                  ),
                  const SizedBox(width: 8),
                  _ToolbarMiniButton(
                    label: 'A-',
                    onTap: onDecreaseTextSize,
                  ),
                  const SizedBox(width: 6),
                  _ToolbarMiniButton(
                    label: 'A+',
                    onTap: onIncreaseTextSize,
                  ),
                ],
                if (showColors) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    height: 28,
                    color: Colors.white.withValues(alpha: 0.09),
                  ),
                  const SizedBox(width: 8),
                  for (final color in colors)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _ColorButton(
                        color: color,
                        selected: activeColor == color,
                        onTap: () => onColorSelected(color),
                      ),
                    ),
                ],
                if (!canUndo) const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: selected ? const Color(0xFF3B404B) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 46,
            height: 42,
            child: Icon(
              icon,
              color: selected ? const Color(0xFF34D399) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: selected ? 24 : 20,
        height: selected ? 24 : 20,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.35),
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _RenderedTextLabel extends StatelessWidget {
  const _RenderedTextLabel({
    required this.text,
    required this.canvasWidth,
  });

  final _EditorText text;
  final double canvasWidth;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: text.rotation,
      child: Transform.scale(
        scale: text.scale,
        alignment: Alignment.topLeft,
        child: Text(
          text.text,
          style: TextStyle(
            color: text.color,
            fontSize: text.fontSize * canvasWidth,
            fontWeight: FontWeight.w700,
            shadows: const [
              Shadow(
                color: Color(0xAA000000),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarMiniButton extends StatelessWidget {
  const _ToolbarMiniButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2E36),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineTextAction extends StatelessWidget {
  const _InlineTextAction({
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? const Color(0xFF34D399) : const Color(0xFF2A2E36),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 18,
            color: highlighted ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _CropHandle extends StatelessWidget {
  const _CropHandle({
    required this.center,
    required this.onStartDrag,
    required this.onUpdateDrag,
    required this.onEndDrag,
  });

  final Offset center;
  final GestureDragStartCallback onStartDrag;
  final GestureDragUpdateCallback onUpdateDrag;
  final GestureDragEndCallback onEndDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - 12,
      top: center.dy - 12,
      child: GestureDetector(
        onPanStart: onStartDrag,
        onPanUpdate: onUpdateDrag,
        onPanEnd: onEndDrag,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF34D399),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkupPainter extends CustomPainter {
  const _MarkupPainter({
    required this.strokes,
    required this.draftStroke,
    required this.shapes,
    required this.draftShape,
    required this.texts,
  });

  final List<_EditorStroke> strokes;
  final _EditorStroke? draftStroke;
  final List<_EditorShape> shapes;
  final _EditorShape? draftShape;
  final List<_EditorText> texts;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in [...strokes, if (draftStroke != null) draftStroke!]) {
      if (stroke.tool == _EditorTool.mosaic) continue;
      final points = stroke.points
          .map((point) => Offset(point.dx * size.width, point.dy * size.height))
          .toList();
      if (points.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < points.length - 1; i++) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }

    for (final shape in [...shapes, if (draftShape != null) draftShape!]) {
      final start =
          Offset(shape.start.dx * size.width, shape.start.dy * size.height);
      final end = Offset(shape.end.dx * size.width, shape.end.dy * size.height);
      final paint = Paint()
        ..color = shape.color
        ..strokeWidth = shape.strokeWidth * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (shape.tool == _EditorTool.rect) {
        canvas.drawRect(Rect.fromPoints(start, end), paint);
      } else if (shape.tool == _EditorTool.arrow) {
        _paintArrow(canvas, start, end, paint);
      }
    }
  }

  void _paintArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final angle = (end - start).direction;
    final wingLength = paint.strokeWidth * 5;
    final wingAngle = 0.55;
    final left = Offset(
      end.dx - wingLength * math.cos(angle - wingAngle),
      end.dy - wingLength * math.sin(angle - wingAngle),
    );
    final right = Offset(
      end.dx - wingLength * math.cos(angle + wingAngle),
      end.dy - wingLength * math.sin(angle + wingAngle),
    );
    canvas.drawLine(end, left, paint);
    canvas.drawLine(end, right, paint);
  }

  @override
  bool shouldRepaint(covariant _MarkupPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.draftStroke != draftStroke ||
        oldDelegate.shapes != shapes ||
        oldDelegate.draftShape != draftShape ||
        oldDelegate.texts != texts;
  }
}

class _MosaicClipper extends CustomClipper<Path> {
  const _MosaicClipper({required this.strokes});

  final List<_EditorStroke> strokes;

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final stroke in strokes) {
      final brushSize = math.max(stroke.strokeWidth * size.width, 18.0);
      if (stroke.points.isEmpty) continue;
      if (stroke.points.length == 1) {
        _addMosaicCell(
          path,
          Offset(
            stroke.points.first.dx * size.width,
            stroke.points.first.dy * size.height,
          ),
          brushSize,
        );
        continue;
      }
      for (var i = 0; i < stroke.points.length - 1; i++) {
        final start = Offset(
          stroke.points[i].dx * size.width,
          stroke.points[i].dy * size.height,
        );
        final end = Offset(
          stroke.points[i + 1].dx * size.width,
          stroke.points[i + 1].dy * size.height,
        );
        final distance = (end - start).distance;
        final steps = math.max((distance / (brushSize * 0.35)).ceil(), 1);
        for (var step = 0; step <= steps; step++) {
          final t = step / steps;
          final point = Offset.lerp(start, end, t)!;
          _addMosaicCell(path, point, brushSize);
        }
      }
    }
    return path;
  }

  void _addMosaicCell(
    Path path,
    Offset point,
    double brushSize,
  ) {
    final snappedLeft = (point.dx / brushSize).floor() * brushSize;
    final snappedTop = (point.dy / brushSize).floor() * brushSize;
    path.addRect(
      Rect.fromLTWH(
        snappedLeft,
        snappedTop,
        brushSize,
        brushSize,
      ),
    );
  }

  @override
  bool shouldReclip(covariant _MosaicClipper oldClipper) {
    return oldClipper.strokes != strokes;
  }
}

class _CropMaskPainter extends CustomPainter {
  const _CropMaskPainter({required this.selectionRect});

  final Rect selectionRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.52);
    final clearPaint = Paint()..blendMode = BlendMode.clear;

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, overlayPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(selectionRect, const Radius.circular(2)),
      clearPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter oldDelegate) {
    return oldDelegate.selectionRect != selectionRect;
  }
}

enum _EditorActionType { stroke, shape, text }

final class _EditorAction {
  _EditorAction.stroke(this.stroke)
      : type = _EditorActionType.stroke,
        shape = null,
        text = null;

  _EditorAction.shape(this.shape)
      : type = _EditorActionType.shape,
        stroke = null,
        text = null;

  _EditorAction.text(this.text)
      : type = _EditorActionType.text,
        stroke = null,
        shape = null;

  final _EditorActionType type;
  final _EditorStroke? stroke;
  final _EditorShape? shape;
  final _EditorText? text;
}
