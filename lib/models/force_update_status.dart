import 'dart:convert';

class ForceUpdateSnapshot {
  static const String sourceVersionCheck = 'version_check';
  static const String sourceResponseInterceptor = 'response_interceptor';
  static const String sourceLocalLock = 'local_lock';

  final bool required;
  final String minVersion;
  final String latestVersion;
  final String? downloadUrl;
  final String? changelog;
  final DateTime checkedAt;
  final String source;
  final int? reasonCode;
  final String message;

  const ForceUpdateSnapshot({
    required this.required,
    required this.minVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.changelog,
    required this.checkedAt,
    required this.source,
    this.reasonCode,
    this.message = '',
  });

  factory ForceUpdateSnapshot.open({
    DateTime? checkedAt,
    String source = sourceVersionCheck,
    String latestVersion = '',
    String minVersion = '',
  }) {
    return ForceUpdateSnapshot(
      required: false,
      minVersion: minVersion,
      latestVersion: latestVersion,
      downloadUrl: null,
      changelog: null,
      checkedAt: checkedAt ?? DateTime.now(),
      source: source,
    );
  }

  bool get hasDownloadUrl {
    final url = downloadUrl?.trim() ?? '';
    return url.isNotEmpty;
  }

  bool get canReleaseRequiredGate {
    return !required && source == sourceVersionCheck;
  }

  Map<String, dynamic> toJson() {
    return {
      'required': required,
      'min_version': minVersion,
      'latest_version': latestVersion,
      'download_url': downloadUrl,
      'changelog': changelog,
      'checked_at': checkedAt.toIso8601String(),
      'source': source,
      'reason_code': reasonCode,
      'message': message,
    };
  }

  factory ForceUpdateSnapshot.fromJson(Map<String, dynamic> json) {
    final checkedAtRaw = json['checked_at']?.toString().trim();
    final checkedAt =
        checkedAtRaw == null || checkedAtRaw.isEmpty
            ? DateTime.now()
            : DateTime.tryParse(checkedAtRaw) ?? DateTime.now();
    return ForceUpdateSnapshot(
      required: _readBool(json['required']) ?? false,
      minVersion: _readString(
        json['min_version'] ?? json['min_supported_version'],
      ),
      latestVersion: _readString(json['latest_version']),
      downloadUrl: _nullableString(json['download_url']),
      changelog: _nullableString(json['changelog']),
      checkedAt: checkedAt,
      source: _readString(json['source']),
      reasonCode: _readInt(json['reason_code'] ?? json['code']),
      message: _readString(json['message']),
    );
  }

  static ForceUpdateSnapshot? fromPersistedLock(String rawJson) {
    final raw = rawJson.trim();
    if (raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final snapshot = ForceUpdateSnapshot.fromJson(decoded);
      if (!snapshot.required) {
        return null;
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  static ForceUpdateSnapshot? tryParseRequiredPayload(
    Object? payload, {
    required String source,
    int? httpStatus,
    String? fallbackMessage,
  }) {
    if (payload is! Map<String, dynamic>) {
      if (httpStatus == 426) {
        return ForceUpdateSnapshot(
          required: true,
          minVersion: '',
          latestVersion: '',
          downloadUrl: null,
          changelog: null,
          checkedAt: DateTime.now(),
          source: source,
          reasonCode: 426,
          message: fallbackMessage?.trim() ?? '',
        );
      }
      return null;
    }

    final candidate = _findCandidateMap(payload);
    final code = _readInt(payload['code']);
    final statusDrivenRequired = httpStatus == 426 || code == 426;
    final requiredFlag =
        _readBool(candidate['force_update']) ??
        _readBool(candidate['required']) ??
        _readBool(candidate['forceUpdate']) ??
        statusDrivenRequired;
    if (requiredFlag != true) {
      return null;
    }

    final latestVersion = _readString(
      candidate['latest_version'] ??
          candidate['latestVersion'] ??
          candidate['version'],
    );
    final minVersion = _readString(
      candidate['min_supported_version'] ??
          candidate['min_version'] ??
          candidate['minimum_version'] ??
          candidate['minVersion'],
    );

    final payloadMessage = _readString(payload['message']);
    final candidateMessage = _readString(candidate['message']);
    final mergedMessage = _mergeMessage(payloadMessage, candidateMessage);

    return ForceUpdateSnapshot(
      required: true,
      minVersion: minVersion,
      latestVersion: latestVersion,
      downloadUrl:
          _nullableString(candidate['download_url']) ??
          _nullableString(candidate['downloadUrl']) ??
          _nullableString(candidate['url']),
      changelog:
          _nullableString(candidate['changelog']) ??
          _nullableString(candidate['release_notes']) ??
          _nullableString(candidate['release_note']),
      checkedAt: DateTime.now(),
      source: source,
      reasonCode: code ?? httpStatus,
      message: mergedMessage,
    );
  }

  static Map<String, dynamic> _findCandidateMap(Map<String, dynamic> root) {
    if (_looksLikeUpdateMap(root)) {
      return root;
    }
    final data = root['data'];
    if (data is Map<String, dynamic> && _looksLikeUpdateMap(data)) {
      return data;
    }
    return root;
  }

  static bool _looksLikeUpdateMap(Map<String, dynamic> map) {
    return map.containsKey('force_update') ||
        map.containsKey('required') ||
        map.containsKey('forceUpdate') ||
        map.containsKey('download_url') ||
        map.containsKey('min_supported_version') ||
        map.containsKey('latest_version');
  }

  static bool? _readBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null) return null;
    return int.tryParse(value.toString().trim());
  }

  static String _readString(Object? value) {
    return value?.toString().trim() ?? '';
  }

  static String? _nullableString(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return raw;
  }

  static String _mergeMessage(String payloadMessage, String candidateMessage) {
    if (candidateMessage.isEmpty || candidateMessage == payloadMessage) {
      return payloadMessage;
    }
    if (payloadMessage.isEmpty) {
      return candidateMessage;
    }
    return '$payloadMessage\n$candidateMessage';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ForceUpdateSnapshot &&
        other.required == required &&
        other.minVersion == minVersion &&
        other.latestVersion == latestVersion &&
        other.downloadUrl == downloadUrl &&
        other.changelog == changelog &&
        other.checkedAt == checkedAt &&
        other.source == source &&
        other.reasonCode == reasonCode &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(
    required,
    minVersion,
    latestVersion,
    downloadUrl,
    changelog,
    checkedAt,
    source,
    reasonCode,
    message,
  );
}
