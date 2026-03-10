import 'dart:math' as math;

import 'package:flutter/material.dart';

class DiceBearAvatarSpec {
  final String style;
  final String seed;

  const DiceBearAvatarSpec({
    required this.style,
    required this.seed,
  });

  static DiceBearAvatarSpec? tryParse(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (host != 'api.dicebear.com' && !host.endsWith('.dicebear.com')) {
      return null;
    }

    final pathSegments = uri.pathSegments;
    if (pathSegments.length < 3) {
      return null;
    }

    final style = pathSegments[1].trim();
    final seed = uri.queryParameters['seed']?.trim() ?? '';
    if (style.isEmpty || seed.isEmpty) {
      return null;
    }

    return DiceBearAvatarSpec(
      style: style,
      seed: seed,
    );
  }

  bool get isRobotStyle => style.contains('bottts') || style.contains('pixel');

  bool get isEmojiStyle =>
      style.contains('emoji') ||
      style.contains('smile') ||
      style.contains('thumb');

  int get hash => _stableHash('$style|$seed');

  int get accentHash => _stableHash('$seed|$style|accent');

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

class DiceBearAvatarFallback extends StatelessWidget {
  final DiceBearAvatarSpec spec;
  final double? width;
  final double? height;

  const DiceBearAvatarFallback({
    super.key,
    required this.spec,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _DiceBearAvatarPainter(spec),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DiceBearAvatarPainter extends CustomPainter {
  final DiceBearAvatarSpec spec;

  const _DiceBearAvatarPainter(this.spec);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final rect = Offset.zero & size;
    final baseHue = (spec.hash % 360).toDouble();
    final accentHue =
        ((baseHue + 42 + (spec.accentHash % 90)) % 360).toDouble();
    final background = HSVColor.fromAHSV(1, baseHue, 0.45, 0.98).toColor();
    final accent = HSVColor.fromAHSV(1, accentHue, 0.55, 0.92).toColor();
    final ink = HSVColor.fromAHSV(1, accentHue, 0.18, 0.22).toColor();
    final highlight = Colors.white.withValues(alpha: 0.18);

    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          background,
          accent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, backgroundPaint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          highlight,
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.3, size.height * 0.25),
          radius: size.shortestSide * 0.6,
        ),
      );
    canvas.drawRect(rect, glowPaint);

    if (spec.isRobotStyle) {
      _paintRobot(canvas, size, ink, highlight);
      return;
    }

    if (spec.isEmojiStyle) {
      _paintEmoji(canvas, size, ink, highlight);
      return;
    }

    _paintPerson(canvas, size, ink, highlight);
  }

  void _paintPerson(
    Canvas canvas,
    Size size,
    Color ink,
    Color highlight,
  ) {
    final w = size.width;
    final h = size.height;
    final skinHue = ((spec.hash ~/ 5) % 40 + 18).toDouble();
    final skin = HSVColor.fromAHSV(1, skinHue, 0.28, 0.96).toColor();
    final hair = HSVColor.fromAHSV(
      1,
      ((spec.accentHash % 360) / 2).toDouble(),
      0.45,
      0.38,
    ).toColor();

    final shouldersPaint = Paint()
      ..color = ink.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final shouldersRect = Rect.fromLTWH(w * 0.16, h * 0.62, w * 0.68, h * 0.34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        shouldersRect,
        Radius.circular(w * 0.18),
      ),
      shouldersPaint,
    );

    final neckPaint = Paint()..color = skin.withValues(alpha: 0.95);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.44, h * 0.46, w * 0.12, h * 0.14),
        Radius.circular(w * 0.04),
      ),
      neckPaint,
    );

    final faceCenter = Offset(w * 0.5, h * 0.38);
    final faceRadius = math.min(w, h) * 0.22;
    final facePaint = Paint()..color = skin;
    canvas.drawCircle(faceCenter, faceRadius, facePaint);

    final hairPaint = Paint()..color = hair;
    final hairPath = Path()
      ..moveTo(
        faceCenter.dx - faceRadius * 1.02,
        faceCenter.dy - faceRadius * 0.2,
      )
      ..quadraticBezierTo(
        faceCenter.dx - faceRadius * 0.95,
        faceCenter.dy - faceRadius * 1.2,
        faceCenter.dx,
        faceCenter.dy - faceRadius * 1.1,
      )
      ..quadraticBezierTo(
        faceCenter.dx + faceRadius * 0.98,
        faceCenter.dy - faceRadius * 1.0,
        faceCenter.dx + faceRadius * 1.02,
        faceCenter.dy - faceRadius * 0.12,
      )
      ..quadraticBezierTo(
        faceCenter.dx + faceRadius * 0.75,
        faceCenter.dy - faceRadius * 0.65,
        faceCenter.dx + faceRadius * 0.18,
        faceCenter.dy - faceRadius * 0.4,
      )
      ..quadraticBezierTo(
        faceCenter.dx - faceRadius * 0.25,
        faceCenter.dy - faceRadius * 0.95,
        faceCenter.dx - faceRadius * 0.8,
        faceCenter.dy - faceRadius * 0.35,
      )
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    final eyePaint = Paint()..color = ink;
    final eyeYOffset = faceRadius * 0.02;
    final leftEye =
        Offset(faceCenter.dx - faceRadius * 0.38, faceCenter.dy - eyeYOffset);
    final rightEye =
        Offset(faceCenter.dx + faceRadius * 0.38, faceCenter.dy - eyeYOffset);
    canvas.drawCircle(leftEye, faceRadius * 0.08, eyePaint);
    canvas.drawCircle(rightEye, faceRadius * 0.08, eyePaint);

    final smilePaint = Paint()
      ..color = ink.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = faceRadius * 0.08
      ..strokeCap = StrokeCap.round;
    final mouthWidth = faceRadius * (0.5 + (spec.hash % 3) * 0.08);
    final mouthRect = Rect.fromCenter(
      center: Offset(faceCenter.dx, faceCenter.dy + faceRadius * 0.28),
      width: mouthWidth,
      height: faceRadius * 0.42,
    );
    canvas.drawArc(mouthRect, 0.25, 2.65, false, smilePaint);

    final nosePaint = Paint()
      ..color = ink.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = faceRadius * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(faceCenter.dx, faceCenter.dy + faceRadius * 0.02),
      Offset(
        faceCenter.dx - faceRadius * 0.05,
        faceCenter.dy + faceRadius * 0.18,
      ),
      nosePaint,
    );

    if ((spec.accentHash & 1) == 0) {
      final glassesPaint = Paint()
        ..color = highlight.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = faceRadius * 0.06;
      final glassesRadius = faceRadius * 0.2;
      canvas.drawCircle(leftEye, glassesRadius, glassesPaint);
      canvas.drawCircle(rightEye, glassesRadius, glassesPaint);
      canvas.drawLine(
        Offset(leftEye.dx + glassesRadius, leftEye.dy),
        Offset(rightEye.dx - glassesRadius, rightEye.dy),
        glassesPaint,
      );
    }
  }

  void _paintRobot(
    Canvas canvas,
    Size size,
    Color ink,
    Color highlight,
  ) {
    final w = size.width;
    final h = size.height;
    final shell = HSVColor.fromAHSV(
      1,
      ((spec.hash % 360) + 180).toDouble() % 360,
      0.15,
      0.96,
    ).toColor();
    final shellShadow = ink.withValues(alpha: 0.15);

    final headRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.22, h * 0.2, w * 0.56, h * 0.48),
      Radius.circular(w * 0.12),
    );
    canvas.drawRRect(headRect, Paint()..color = shellShadow);
    canvas.drawRRect(
      headRect.shift(Offset(0, -h * 0.015)),
      Paint()..color = shell,
    );

    final antennaPaint = Paint()
      ..color = ink.withValues(alpha: 0.75)
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.5, h * 0.1),
      Offset(w * 0.5, h * 0.22),
      antennaPaint,
    );
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.08),
      w * 0.045,
      Paint()..color = highlight.withValues(alpha: 0.8),
    );

    final eyePaint = Paint()..color = ink.withValues(alpha: 0.85);
    final eyeWidth = w * 0.1;
    final eyeHeight = h * 0.08;
    final eyeRadius = Radius.circular(w * 0.03);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.33, h * 0.34, eyeWidth, eyeHeight),
        eyeRadius,
      ),
      eyePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.57, h * 0.34, eyeWidth, eyeHeight),
        eyeRadius,
      ),
      eyePaint,
    );

    final mouthPaint = Paint()
      ..color = ink.withValues(alpha: 0.7)
      ..strokeWidth = h * 0.025
      ..strokeCap = StrokeCap.round;
    final mouthY = h * 0.53;
    for (var i = 0; i < 4; i++) {
      final x = w * (0.36 + i * 0.09);
      canvas.drawLine(
        Offset(x, mouthY),
        Offset(x + w * 0.05, mouthY),
        mouthPaint,
      );
    }

    final bodyPaint = Paint()..color = shell.withValues(alpha: 0.86);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.3, h * 0.68, w * 0.4, h * 0.18),
        Radius.circular(w * 0.08),
      ),
      bodyPaint,
    );
  }

  void _paintEmoji(
    Canvas canvas,
    Size size,
    Color ink,
    Color highlight,
  ) {
    final w = size.width;
    final h = size.height;
    final faceCenter = Offset(w * 0.5, h * 0.5);
    final faceRadius = math.min(w, h) * 0.28;
    final faceColor = HSVColor.fromAHSV(
      1,
      ((spec.hash % 40) + 28).toDouble(),
      0.62,
      1,
    ).toColor();

    canvas.drawCircle(faceCenter, faceRadius, Paint()..color = faceColor);
    canvas.drawCircle(
      Offset(
        faceCenter.dx - faceRadius * 0.25,
        faceCenter.dy - faceRadius * 0.18,
      ),
      faceRadius * 0.1,
      Paint()..color = ink,
    );
    canvas.drawCircle(
      Offset(
        faceCenter.dx + faceRadius * 0.25,
        faceCenter.dy - faceRadius * 0.18,
      ),
      faceRadius * 0.1,
      Paint()..color = ink,
    );

    final mouthPaint = Paint()
      ..color = ink.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = faceRadius * 0.11
      ..strokeCap = StrokeCap.round;
    final smileVariant = spec.accentHash % 3;
    final mouthRect = Rect.fromCenter(
      center: Offset(faceCenter.dx, faceCenter.dy + faceRadius * 0.1),
      width: faceRadius * 0.95,
      height: faceRadius * 0.75,
    );
    if (smileVariant == 0) {
      canvas.drawArc(mouthRect, 0.35, 2.45, false, mouthPaint);
    } else if (smileVariant == 1) {
      canvas.drawArc(mouthRect, 0.1, 2.9, false, mouthPaint);
    } else {
      canvas.drawArc(mouthRect, 0.55, 2.0, false, mouthPaint);
    }

    final cheekPaint = Paint()
      ..color = highlight.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(
        faceCenter.dx - faceRadius * 0.42,
        faceCenter.dy + faceRadius * 0.08,
      ),
      faceRadius * 0.13,
      cheekPaint,
    );
    canvas.drawCircle(
      Offset(
        faceCenter.dx + faceRadius * 0.42,
        faceCenter.dy + faceRadius * 0.08,
      ),
      faceRadius * 0.13,
      cheekPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DiceBearAvatarPainter oldDelegate) {
    return oldDelegate.spec.style != spec.style ||
        oldDelegate.spec.seed != spec.seed;
  }
}
