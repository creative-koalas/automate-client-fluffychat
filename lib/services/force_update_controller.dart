import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/api_client.dart';
import '../models/force_update_status.dart';
import '../utils/app_update_service.dart';
import '../utils/platform_infos.dart';
import 'force_update_bus.dart';

class ForceUpdateController extends ChangeNotifier with WidgetsBindingObserver {
  ForceUpdateController(
    this._api, {
    BuildContext? Function()? dialogContextProvider,
  }) : _dialogContextProvider = dialogContextProvider;

  static const String _lockStorageKey = 'force_update_lock_v1';
  static const Duration _foregroundPollInterval = Duration(minutes: 5);
  static const Duration _backgroundPollInterval = Duration(minutes: 15);

  final PsygoApiClient _api;
  final BuildContext? Function()? _dialogContextProvider;

  ForceUpdateSnapshot _status = ForceUpdateSnapshot.open(
    source: ForceUpdateSnapshot.sourceVersionCheck,
  );
  AppLifecycleState _lifecycleState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _hasLoaded = false;
  bool _disposed = false;
  bool _updateActionInFlight = false;
  bool _showingUpdateDialog = false;

  ForceUpdateSnapshot get status => _status;
  bool get isRequired => _status.required;
  bool get isRefreshing => _refreshInFlight;
  bool get hasLoaded => _hasLoaded;
  bool get isUpdateActionInFlight => _updateActionInFlight;
  bool get isShowingUpdateDialog => _showingUpdateDialog;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    ForceUpdateBus.instance.notifier.addListener(_handleBusUpdate);
    _restartPolling();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _restoreLock();
    _handleBusUpdate();
    await refreshStatus();
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
      final currentVersion = await PlatformInfos.getVersion();
      final platform = _platformName;
      final response = await _api.checkAppVersion(
        currentVersion: currentVersion,
        platform: platform,
        publishForceUpdate: false,
      );

      final snapshot = ForceUpdateSnapshot(
        required: response.forceUpdate,
        minVersion: response.minSupportedVersion,
        latestVersion: response.latestVersion,
        downloadUrl: response.downloadUrl,
        changelog: response.changelog,
        checkedAt: DateTime.now(),
        source: ForceUpdateSnapshot.sourceVersionCheck,
      );
      await _applySnapshot(snapshot, allowRelease: true);
      ForceUpdateBus.instance.publish(snapshot);
    } catch (e) {
      debugPrint('[ForceUpdate] refresh status failed: $e');
    } finally {
      _refreshInFlight = false;
      _notifyListenersIfAlive();
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(refreshStatus());
      }
    }
  }

  Future<void> openUpdateDialog(BuildContext context) async {
    if (!isRequired || _updateActionInFlight) {
      return;
    }
    _updateActionInFlight = true;
    _showingUpdateDialog = true;
    _notifyListenersIfAlive();
    try {
      final dialogContext = _dialogContextProvider?.call() ?? context;
      final service = AppUpdateService(_api);
      await service.showForceUpdateDialog(
        context: dialogContext,
        snapshot: _status,
      );
    } finally {
      _showingUpdateDialog = false;
      _updateActionInFlight = false;
      _notifyListenersIfAlive();
      await refreshStatus();
    }
  }

  void _handleBusUpdate() {
    final snapshot = ForceUpdateBus.instance.current;
    if (snapshot == null) {
      return;
    }
    final allowRelease = snapshot.canReleaseRequiredGate;
    unawaited(_applySnapshot(snapshot, allowRelease: allowRelease));
  }

  Future<void> _applySnapshot(
    ForceUpdateSnapshot next, {
    required bool allowRelease,
  }) async {
    if (next.required) {
      final changed = !_hasLoaded || !_status.required || _status != next;
      _status = next;
      _hasLoaded = true;
      await _persistRequiredLock(next);
      if (changed) {
        _notifyListenersIfAlive();
      }
      return;
    }

    if (_status.required && !allowRelease) {
      return;
    }

    final changed = !_hasLoaded || _status.required || _status != next;
    _status = next;
    _hasLoaded = true;
    await _clearPersistedLock();
    if (changed) {
      _notifyListenersIfAlive();
    }
  }

  Future<void> _restoreLock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lockStorageKey) ?? '';
      final snapshot = ForceUpdateSnapshot.fromPersistedLock(raw);
      if (snapshot == null) {
        return;
      }
      _status = ForceUpdateSnapshot(
        required: true,
        minVersion: snapshot.minVersion,
        latestVersion: snapshot.latestVersion,
        downloadUrl: snapshot.downloadUrl,
        changelog: snapshot.changelog,
        checkedAt: snapshot.checkedAt,
        source: ForceUpdateSnapshot.sourceLocalLock,
        reasonCode: snapshot.reasonCode,
        message: snapshot.message,
      );
      _hasLoaded = true;
      _notifyListenersIfAlive();
    } catch (e) {
      debugPrint('[ForceUpdate] restore lock failed: $e');
    }
  }

  Future<void> _persistRequiredLock(ForceUpdateSnapshot snapshot) async {
    if (!snapshot.required) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lockStorageKey, jsonEncode(snapshot.toJson()));
    } catch (e) {
      debugPrint('[ForceUpdate] persist lock failed: $e');
    }
  }

  Future<void> _clearPersistedLock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lockStorageKey);
    } catch (e) {
      debugPrint('[ForceUpdate] clear lock failed: $e');
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

  String get _platformName {
    if (PlatformInfos.isWeb) return 'web';
    if (PlatformInfos.isAndroid) return 'android';
    if (PlatformInfos.isIOS) return 'ios';
    if (PlatformInfos.isWindows) return 'windows';
    if (PlatformInfos.isMacOS) return 'macos';
    if (PlatformInfos.isLinux) return 'linux';
    return 'unknown';
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
    ForceUpdateBus.instance.notifier.removeListener(_handleBusUpdate);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
