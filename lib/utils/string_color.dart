import 'package:flutter/material.dart';

extension StringColor on String {
  static final _colorCache = <String, Map<double, Color>>{};

  Color _getColorLight(double light) {
    var number = 0.0;
    for (var i = 0; i < length; i++) {
      number += codeUnitAt(i);
    }
    number = (number % 12) * 25.5;
    return HSLColor.fromAHSL(0.75, number, 1, light).toColor();
  }

  Color get color {
    _colorCache[this] ??= {};
    return _colorCache[this]![0.3] ??= _getColorLight(0.3);
  }

  Color get darkColor {
    _colorCache[this] ??= {};
    return _colorCache[this]![0.2] ??= _getColorLight(0.2);
  }

  Color get lightColorText {
    _colorCache[this] ??= {};
    return _colorCache[this]![0.7] ??= _getColorLight(0.7);
  }

  Color get lightColorAvatar {
    _colorCache[this] ??= {};
    final color = _colorCache[this]![0.45] ??= _getColorLight(0.45);

    // Color correction parameters - adjust these to tune the colors
    const saturationCorrection = 1.0; // 0.0-1.0, lower = less saturated
    const lightnessCorrection = 1.0; // > 1.0 = lighter, < 1.0 = darker

    final hsl = HSLColor.fromColor(color);
    final correctedHsl = hsl.withSaturation((hsl.saturation * saturationCorrection).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * lightnessCorrection).clamp(0.0, 1.0));

    return correctedHsl.toColor();
  }
}
