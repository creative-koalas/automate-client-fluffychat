import 'package:censor_it/censor_it.dart';

/// 检查文本是否包含不当内容
bool containsProfanity(String text) {
  if (text.trim().isEmpty) return false;
  final censor = CensorIt.mask(text, pattern: LanguagePattern.all);
  return censor.hasProfanity;
}
