import 'package:flutter/foundation.dart';

import '../models/maintenance_status.dart';

class MaintenanceStatusBus {
  MaintenanceStatusBus._();

  static final MaintenanceStatusBus instance = MaintenanceStatusBus._();

  final ValueNotifier<MaintenanceStatusSnapshot?> notifier =
      ValueNotifier<MaintenanceStatusSnapshot?>(null);

  MaintenanceStatusSnapshot? get current => notifier.value;

  void publish(MaintenanceStatusSnapshot status) {
    if (notifier.value == status) {
      return;
    }
    notifier.value = status;
  }
}
