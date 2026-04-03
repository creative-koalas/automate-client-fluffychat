import 'package:flutter/foundation.dart';

import '../models/force_update_status.dart';

class ForceUpdateBus {
  ForceUpdateBus._();

  static final ForceUpdateBus instance = ForceUpdateBus._();

  final ValueNotifier<ForceUpdateSnapshot?> notifier =
      ValueNotifier<ForceUpdateSnapshot?>(null);

  ForceUpdateSnapshot? get current => notifier.value;

  void publish(ForceUpdateSnapshot snapshot) {
    if (notifier.value == snapshot) {
      return;
    }
    notifier.value = snapshot;
  }
}
