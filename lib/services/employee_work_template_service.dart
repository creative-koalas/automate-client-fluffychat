import 'package:psygo/core/api_client.dart';

class EmployeeWorkTemplateConfig {
  final String templateId;
  final String title;
  final String description;
  final String message;
  final int order;
  final bool enabled;

  const EmployeeWorkTemplateConfig({
    required this.templateId,
    required this.title,
    required this.description,
    required this.message,
    required this.order,
    required this.enabled,
  });

  factory EmployeeWorkTemplateConfig.fromJson(Map<String, dynamic> json) {
    String readString(String key) => (json[key] as String?)?.trim() ?? '';

    final rawOrder = json['order'];
    int order = 0;
    if (rawOrder is int) {
      order = rawOrder;
    } else if (rawOrder is num) {
      order = rawOrder.toInt();
    } else if (rawOrder != null) {
      order = int.tryParse(rawOrder.toString()) ?? 0;
    }
    if (order < 0) {
      order = 0;
    }

    final rawEnabled = json['enabled'];
    var enabled = true;
    if (rawEnabled is bool) {
      enabled = rawEnabled;
    } else if (rawEnabled is num) {
      enabled = rawEnabled != 0;
    } else if (rawEnabled is String) {
      final normalized = rawEnabled.trim().toLowerCase();
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        enabled = false;
      } else if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes') {
        enabled = true;
      }
    }

    return EmployeeWorkTemplateConfig(
      templateId: readString('template_id'),
      title: readString('title'),
      description: readString('description'),
      message: readString('message'),
      order: order,
      enabled: enabled,
    );
  }
}

class EmployeeWorkTemplateService {
  EmployeeWorkTemplateService._();

  static final EmployeeWorkTemplateService instance =
      EmployeeWorkTemplateService._();

  final PsygoApiClient _apiClient = PsygoApiClient();
  static const Duration _cacheTtl = Duration(minutes: 5);

  List<EmployeeWorkTemplateConfig> _cache = const [];
  DateTime? _cachedAt;

  Future<List<EmployeeWorkTemplateConfig>> getTemplates({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _freshCache();
      if (cached != null) {
        return cached;
      }
    }

    try {
      final response = await _apiClient.get<List<dynamic>>(
        '/api/employee-work-templates',
        fromJsonT: (data) {
          if (data is Map<String, dynamic>) {
            final templates = data['templates'];
            if (templates is List) {
              return templates;
            }
          }
          if (data is List) {
            return data;
          }
          return <dynamic>[];
        },
      );

      final parsed = (response.data ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => EmployeeWorkTemplateConfig.fromJson(
                item.cast<String, dynamic>(),
              ))
          .where(
            (item) =>
                item.templateId.isNotEmpty &&
                item.title.isNotEmpty &&
                item.description.isNotEmpty &&
                item.message.isNotEmpty,
          )
          .toList(growable: false);

      final sorted = parsed.toList(growable: true)
        ..sort((a, b) {
          if (a.order == b.order) {
            return a.templateId.compareTo(b.templateId);
          }
          return a.order.compareTo(b.order);
        });

      _cache = List<EmployeeWorkTemplateConfig>.unmodifiable(sorted);
      _cachedAt = DateTime.now();
      return List<EmployeeWorkTemplateConfig>.from(_cache);
    } catch (_) {
      return List<EmployeeWorkTemplateConfig>.from(_cache);
    }
  }

  List<EmployeeWorkTemplateConfig>? _freshCache() {
    if (_cache.isEmpty || _cachedAt == null) {
      return null;
    }
    final age = DateTime.now().difference(_cachedAt!);
    if (age <= _cacheTtl) {
      return List<EmployeeWorkTemplateConfig>.from(_cache);
    }
    return null;
  }
}
