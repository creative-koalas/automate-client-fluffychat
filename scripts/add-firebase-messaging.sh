#!/usr/bin/env bash

set -euo pipefail

flutter pub add fcm_shared_isolate:0.1.0
flutter pub get

fcm_service_file="$(find android/app/src/main/kotlin -type f -name 'FcmPushService.kt' | head -n1 || true)"

if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's,//<GOOGLE_SERVICES>,,g' lib/utils/background_push.dart
  if [[ -n "$fcm_service_file" ]]; then
    sed -i '' -e 's,^/\*,,' -e 's,\*/$,,' "$fcm_service_file"
  fi
else
  sed -i 's,//<GOOGLE_SERVICES>,,g' lib/utils/background_push.dart
  if [[ -n "$fcm_service_file" ]]; then
    sed -i -e 's,^/\*,,' -e 's,\*/$,,' "$fcm_service_file"
  fi
fi
