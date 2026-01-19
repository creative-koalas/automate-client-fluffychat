/// Agent 风格相关模型
library;

/// 风格选项
class StyleOption {
  final String key;
  final String title;

  const StyleOption({
    required this.key,
    required this.title,
  });

  factory StyleOption.fromJson(Map<String, dynamic> json) {
    return StyleOption(
      key: json['key'] as String,
      title: json['title'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'title': title,
    };
  }
}

/// 可用风格列表响应
class AvailableStyles {
  final List<StyleOption> communicationStyles;
  final List<StyleOption> reportStyles;

  const AvailableStyles({
    required this.communicationStyles,
    required this.reportStyles,
  });

  factory AvailableStyles.fromJson(Map<String, dynamic> json) {
    return AvailableStyles(
      communicationStyles: (json['communication_styles'] as List<dynamic>)
          .map((e) => StyleOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      reportStyles: (json['report_styles'] as List<dynamic>)
          .map((e) => StyleOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
