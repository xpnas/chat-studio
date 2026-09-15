#!/usr/bin/env bash
# Validate a signed, non-debuggable APK before handing it to a tester.
set -euo pipefail
APK="${1:?Usage: bash scripts/verify-android-release.sh /path/to/app-release.apk}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$SDK" && -f "$APK" ]] || { echo 'Set ANDROID_HOME and pass an existing APK' >&2; exit 1; }
TOOLS="$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
"$TOOLS/apksigner" verify --verbose --print-certs "$APK"
INFO="$("$TOOLS/aapt" dump badging "$APK")"
if grep -q '^application-debuggable' <<< "$INFO"; then
  echo 'Refusing debuggable package as Release' >&2
  exit 1
fi
grep -E "^package:|^sdkVersion:|^targetSdkVersion:|^native-code:" <<< "$INFO"
python3 - "$APK" <<'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    entries=archive.namelist()
    assert any(e.endswith('/libapp.so') for e in entries), 'Missing Dart AOT library'
    assert 'assets/flutter_assets/kernel_blob.bin' not in entries, 'Unexpected debug kernel'
print('Release AOT verified; no debug kernel.')
PY
sha256sum "$APK"
