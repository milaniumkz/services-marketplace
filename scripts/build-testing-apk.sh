#!/usr/bin/env bash
# Optimized APK signed with the Android TEST key. Never use for a store release.
set -euo pipefail
cd "$(dirname "$0")/.."
joba_api_url="${JOBA_API_URL:-https://188-241-217-228.sslip.io}"
[[ "$joba_api_url" == https://* ]] || { echo 'Testing APK requires an HTTPS API endpoint' >&2; exit 2; }
joba_source="${JOBA_APK_SOURCE_COMMIT:-$(git rev-parse HEAD)}"
[[ "$joba_source" =~ ^[0-9a-f]{40}$ ]] || exit 2
if [[ "${1:-}" != --package-existing ]]; then
  bash scripts/flutter-mobile.sh build apk --release --no-pub --dart-define="JOBA_API_URL=$joba_api_url"
fi
joba_sdk="${ANDROID_HOME:-/workspace/android-sdk}"
joba_tools="$(find "$joba_sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
joba_key="${ANDROID_USER_HOME:-/workspace/.android}/debug.keystore"
[[ -f "$joba_key" ]] || { echo 'Build a debug APK once to create the local Android test key' >&2; exit 1; }
joba_output="release/testing/$joba_source"
mkdir -p "$joba_output"
"$joba_tools/apksigner" sign --ks "$joba_key" --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out "$joba_output/JOBA-testing.apk" apps/mobile/build/app/outputs/flutter-apk/app-release.apk
"$joba_tools/apksigner" verify --verbose --print-certs "$joba_output/JOBA-testing.apk" > "$joba_output/signature.txt"
"$joba_tools/zipalign" -c -P 16 4 "$joba_output/JOBA-testing.apk"
"$joba_tools/aapt" dump badging "$joba_output/JOBA-testing.apk" > "$joba_output/package.txt"
JOBA_APK_MANIFEST_SOURCE="$joba_source" JOBA_APK_MANIFEST_URL="$joba_api_url" JOBA_APK_MANIFEST_DIR="$joba_output" python3 - <<'PY'
import hashlib,json,os,datetime
from pathlib import Path
root=Path(os.environ['JOBA_APK_MANIFEST_DIR']);apk=root/'JOBA-testing.apk'
hash=hashlib.sha256(apk.read_bytes()).hexdigest()
(root/'JOBA-testing.apk.sha256').write_text(hash+'  JOBA-testing.apk\n')
(root/'build.json').write_text(json.dumps({'source_commit':os.environ['JOBA_APK_MANIFEST_SOURCE'],'api_url':os.environ['JOBA_APK_MANIFEST_URL'],'built_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'package':'kz.joba.services_marketplace','build_mode':'release','signing':'Android debug/test certificate; not for store publication','sha256':hash,'size_bytes':apk.stat().st_size,'physical_device_tested':False,'advertising_sdks_integrated':False},ensure_ascii=False,indent=2)+'\n')
print(str(apk),apk.stat().st_size,'bytes; SHA-256',hash)
PY
