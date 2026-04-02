#!/bin/sh
set -eu

# Post-process app display names from --dart-define APP_NAME.
# This keeps iOS display names aligned with Android's APP_NAME flow.

extract_app_name_from_dart_defines() {
  python3 - <<'PY'
import base64
import os

defines = os.environ.get("DART_DEFINES", "")
for item in defines.split(","):
    item = item.strip()
    if not item:
        continue
    try:
        decoded = base64.b64decode(item).decode("utf-8")
    except Exception:
        continue
    if decoded.startswith("APP_NAME="):
        value = decoded.split("=", 1)[1].strip()
        if value:
            print(value)
            break
PY
}

set_plist_key() {
  plist_path="$1"
  key="$2"
  value="$3"
  if [ ! -f "${plist_path}" ]; then
    return 0
  fi

  python3 - "${plist_path}" "${key}" "${value}" <<'PY'
import plistlib
import sys

plist_path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(plist_path, "rb") as f:
    data = plistlib.load(f)
data[key] = value
with open(plist_path, "wb") as f:
    plistlib.dump(data, f)
PY
}

APP_NAME="$(extract_app_name_from_dart_defines || true)"
if [ -z "${APP_NAME}" ]; then
  APP_NAME="${APP_DISPLAY_NAME:-}"
fi
if [ -z "${APP_NAME}" ]; then
  exit 0
fi

# Main app bundle display name.
MAIN_PLIST="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Info.plist"
set_plist_key "${MAIN_PLIST}" "CFBundleDisplayName" "${APP_NAME}"
set_plist_key "${MAIN_PLIST}" "CFBundleName" "${APP_NAME}"
