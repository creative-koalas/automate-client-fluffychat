import 'package:psygo/core/api_client.dart';

class QuickTipTemplateConfig {
  final String intentId;
  final String title;
  final String placeholder;
  final String serverPrompt;
  final int order;
  final bool enabled;

  const QuickTipTemplateConfig({
    required this.intentId,
    required this.title,
    required this.placeholder,
    required this.serverPrompt,
    required this.order,
    required this.enabled,
  });

  factory QuickTipTemplateConfig.fromJson(Map<String, dynamic> json) {
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

    return QuickTipTemplateConfig(
      intentId: readString('intent_id'),
      title: readString('title'),
      placeholder: readString('placeholder'),
      serverPrompt: readString('server_prompt'),
      order: order,
      enabled: enabled,
    );
  }
}

class QuickTipTemplateService {
  QuickTipTemplateService._();

  static final QuickTipTemplateService instance = QuickTipTemplateService._();

  final PsygoApiClient _apiClient = PsygoApiClient();
  static const Duration _cacheTtl = Duration(minutes: 5);

  List<QuickTipTemplateConfig> _cache = const [];
  DateTime? _cachedAt;

  Future<List<QuickTipTemplateConfig>> getTemplates({
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
        '/api/quick-tip-templates',
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
          .map((item) => QuickTipTemplateConfig.fromJson(
                item.cast<String, dynamic>(),
              ))
          .where(
            (item) =>
                item.intentId.isNotEmpty &&
                item.title.isNotEmpty &&
                item.placeholder.isNotEmpty,
          )
          .toList(growable: false);

      final sorted = parsed.toList(growable: true)
        ..sort((a, b) {
          if (a.order == b.order) {
            return a.intentId.compareTo(b.intentId);
          }
          return a.order.compareTo(b.order);
        });

      _cache = List<QuickTipTemplateConfig>.unmodifiable(sorted);
      _cachedAt = DateTime.now();
      return List<QuickTipTemplateConfig>.from(_cache);
    } catch (_) {
      return List<QuickTipTemplateConfig>.from(_cache);
    }
  }

  List<QuickTipTemplateConfig>? _freshCache() {
    if (_cache.isEmpty || _cachedAt == null) {
      return null;
    }
    final age = DateTime.now().difference(_cachedAt!);
    if (age <= _cacheTtl) {
      return List<QuickTipTemplateConfig>.from(_cache);
    }
    return null;
  }
}
