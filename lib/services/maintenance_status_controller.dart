import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../backend/backend.dart';
import '../models/maintenance_status.dart';
import 'maintenance_status_bus.dart';

class MaintenanceStatusController extends ChangeNotifier
    with WidgetsBindingObserver {
  MaintenanceStatusController(this._api);

  static const Duration _foregroundPollInterval = Duration(seconds: 10);
  static const Duration _backgroundPollInterval = Duration(seconds: 30);

  final PsygoApiClient _api;

  MaintenanceStatusSnapshot _status = const MaintenanceStatusSnapshot.open();
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _hasLoaded = false;
  bool _disposed = false;

  MaintenanceStatusSnapshot get status => _status;
  bool get isClosed => _status.closed;
  bool get isRefreshing => _refreshInFlight;
  bool get hasLoaded => _hasLoaded;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    MaintenanceStatusBus.instance.notifier.addListener(_handleBusUpdate);
    _handleBusUpdate();
    _restartPolling();
    unawaited(refreshStatus());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _restartPolling();
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshStatus());
    }
  }

  Future<void> refreshStatus() async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }

    _refreshInFlight = true;
    _notifyListenersIfAlive();
    try {
      final status = await _api.getMaintenanceStatus();
      _applyStatus(status);
    } catch (e) {
      debugPrint('[Maintenance] refresh status failed: $e');
    } finally {
      _refreshInFlight = false;
      _notifyListenersIfAlive();
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(refreshStatus());
      }
    }
  }

  void _handleBusUpdate() {
    final status = MaintenanceStatusBus.instance.current;
    if (status == null) {
      return;
    }
    _applyStatus(status);
  }

  void _applyStatus(MaintenanceStatusSnapshot next) {
    final changed = !_hasLoaded || next != _status;
    _status = next;
    _hasLoaded = true;
    if (changed) {
      _notifyListenersIfAlive();
    }
  }

  void _restartPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollIntervalForState(), (_) {
      unawaited(refreshStatus());
    });
  }

  Duration _pollIntervalForState() {
    switch (_lifecycleState) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        return _foregroundPollInterval;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        return _backgroundPollInterval;
    }
  }

  void _notifyListenersIfAlive() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    MaintenanceStatusBus.instance.notifier.removeListener(_handleBusUpdate);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
