class MaintenanceStatusSnapshot {
  final String state;
  final bool closed;
  final String reason;
  final DateTime? updatedAt;

  const MaintenanceStatusSnapshot({
    required this.state,
    required this.closed,
    this.reason = '',
    this.updatedAt,
  });

  const MaintenanceStatusSnapshot.open()
      : state = 'OPEN',
        closed = false,
        reason = '',
        updatedAt = null;

  factory MaintenanceStatusSnapshot.fromPublicJson(
    Map<String, dynamic> json,
  ) {
    final closed = _readBool(json['closed']) ?? false;
    return MaintenanceStatusSnapshot(
      state: _normalizeState(
        json['state'],
        fallback: closed ? 'MAINTENANCE' : 'OPEN',
      ),
      closed: closed,
      reason: _readString(json['reason']),
      updatedAt: _readDateTime(json['updated_at'] ?? json['updatedAt']),
    );
  }

  static MaintenanceStatusSnapshot? tryParsePublicPayload(Object? payload) {
    if (payload is! Map<String, dynamic> || !payload.containsKey('closed')) {
      return null;
    }
    return MaintenanceStatusSnapshot.fromPublicJson(payload);
  }

  static MaintenanceStatusSnapshot? tryParseClosedErrorPayload(Object? payload) {
    if (payload is! Map<String, dynamic>) {
      return null;
    }

    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      return null;
    }

    if (_readBool(data['closed']) != true) {
      return null;
    }

    final reason = _readString(data['reason']);

    return MaintenanceStatusSnapshot(
      state: _normalizeState(
        payload['state'] ?? data['state'],
        fallback: 'MAINTENANCE',
      ),
      closed: true,
      reason: reason.isNotEmpty ? reason : _readString(payload['message']),
      updatedAt: _readDateTime(payload['updated_at'] ?? data['updated_at']),
    );
  }

  static bool? _readBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return null;
  }

  static String _readString(Object? value) {
    final result = value?.toString().trim() ?? '';
    return result;
  }

  static String _normalizeState(
    Object? value, {
    required String fallback,
  }) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return fallback;
    }
    return normalized;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is DateTime) {
      return value;
    }
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is MaintenanceStatusSnapshot &&
        other.state == state &&
        other.closed == closed &&
        other.reason == reason &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(state, closed, reason, updatedAt);
}
