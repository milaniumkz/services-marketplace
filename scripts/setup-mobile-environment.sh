#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
export PUB_CACHE="${PUB_CACHE:-/workspace/.pub-cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/workspace/.config}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-/workspace/.android}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/workspace/.gradle}"
export FLUTTER_ROOT="${FLUTTER_ROOT:-/workspace/flutter-sdk}"
export ANDROID_HOME="${ANDROID_HOME:-/workspace/android-sdk}"
mkdir -p "$PUB_CACHE" "$XDG_CONFIG_HOME" "$ANDROID_USER_HOME" "$GRADLE_USER_HOME"
if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  git clone --depth 1 --branch 3.35.7 https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
fi
[[ "$(git -C "$FLUTTER_ROOT" rev-parse HEAD)" == adc901062556672b4138e18a4dc62a4be8f4b3c2 ]] || {
  echo 'The configured Flutter SDK differs from the tested pin; update the pin deliberately.' >&2; exit 1;
}
joba_existing_javac="$(find /workspace/joba-jdk -maxdepth 3 -path '*/bin/javac' -type f 2>/dev/null | head -1 || true)"
if [[ -z "$joba_existing_javac" ]]; then
  temp_dir="$(mktemp -d /tmp/joba-jdk-install.XXXXXX)"
  curl -fLsS --max-time 180 https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz -o "$temp_dir/jdk.tar.gz"
  curl -fLsS --max-time 30 https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz.sha256 -o "$temp_dir/jdk.sha256"
  python3 - "$temp_dir" <<'PY'
from pathlib import Path
import hashlib,sys,tarfile
root=Path(sys.argv[1]);archive=root/'jdk.tar.gz'
assert hashlib.sha256(archive.read_bytes()).hexdigest()==(root/'jdk.sha256').read_text().strip().split()[0], 'JDK checksum mismatch'
with tarfile.open(archive) as source:source.extractall('/workspace/joba-jdk',filter='data')
PY
  rm -rf "$temp_dir"
fi
joba_jdk_dir="$(find /workspace/joba-jdk -mindepth 1 -maxdepth 1 -type d -name 'jdk-21*' | sort -V | tail -1)"
export JAVA_HOME="$joba_jdk_dir"
[[ -x "$JAVA_HOME/bin/javac" ]] || { echo 'A full JDK 21 is required, not only the Java runtime.' >&2; exit 1; }
if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  temp_dir="$(mktemp -d /tmp/joba-android-install.XXXXXX)"
  curl -fLsS --max-time 180 https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip -o "$temp_dir/tools.zip"
  python3 - "$temp_dir/tools.zip" "$ANDROID_HOME" <<'PY'
from pathlib import Path
import hashlib,sys,zipfile
archive=Path(sys.argv[1]);sdk=Path(sys.argv[2])
assert hashlib.sha1(archive.read_bytes()).hexdigest()=='e025545c62a8e64c7559119566a569fb1dec5f60', 'Android tools checksum mismatch'
zipfile.ZipFile(archive).extractall(sdk/'cmdline-tools')
(sdk/'cmdline-tools/cmdline-tools').rename(sdk/'cmdline-tools/latest')
for file in (sdk/'cmdline-tools/latest/bin').iterdir():file.chmod(0o755)
PY
  rm -rf "$temp_dir"
fi
python3 - <<'PY'
import os,urllib.parse
from pathlib import Path
proxy=urllib.parse.urlparse(os.environ.get('HTTPS_PROXY',''))
path=Path(os.environ['GRADLE_USER_HOME'])/'gradle.properties'
# Existing user Gradle configuration is preserved; no credentials are copied.
if proxy.hostname and not path.exists():
    text=''.join(f'systemProp.{scheme}.proxyHost={proxy.hostname}\nsystemProp.{scheme}.proxyPort={proxy.port or 80}\n' for scheme in ['http','https'])
    text+='systemProp.javax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts\nsystemProp.http.nonProxyHosts=localhost|127.*\norg.gradle.workers.max=2\n'
    path.write_text(text)
PY
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" --licenses < <(yes) > /tmp/joba-sdk-licenses.log 2>&1
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" 'platform-tools' 'platforms;android-36' 'platforms;android-34' 'platforms;android-35' 'build-tools;35.0.0' 'ndk;27.0.12077973' 'cmake;3.22.1'
cd "$repo_dir/apps/mobile"
"$FLUTTER_ROOT/bin/flutter" pub get --enforce-lockfile
"$FLUTTER_ROOT/bin/flutter" test --reporter expanded test/widget_test.dart test/local_lock_test.dart
