#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
export FLUTTER_ROOT="${FLUTTER_ROOT:-/workspace/flutter-sdk}"
export PUB_CACHE="${PUB_CACHE:-/workspace/.pub-cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/workspace/.config}"
export ANDROID_HOME="${ANDROID_HOME:-/workspace/android-sdk}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-/workspace/.android}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/workspace/.gradle}"
if [[ -z "${JAVA_HOME:-}" && -d /workspace/joba-jdk ]]; then
  joba_jdk_dir="$(find /workspace/joba-jdk -mindepth 1 -maxdepth 1 -type d -name 'jdk-21*' | sort -V | tail -1)"
  if [[ -n "$joba_jdk_dir" ]]; then export JAVA_HOME="$joba_jdk_dir"; fi
fi
if [[ -n "${HTTPS_PROXY:-}" ]]; then
  joba_proxy_opts="$(python3 - <<'PYPROXY'
import os,urllib.parse
p=urllib.parse.urlparse(os.environ['HTTPS_PROXY'])
if p.hostname:
 print(f'-Dhttps.proxyHost={p.hostname} -Dhttps.proxyPort={p.port or 80} -Dhttp.proxyHost={p.hostname} -Dhttp.proxyPort={p.port or 80} -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts')
PYPROXY
)"
  export JAVA_OPTS="${JAVA_OPTS:-} $joba_proxy_opts"
fi
cd "$repo_dir/apps/mobile"
exec "$FLUTTER_ROOT/bin/flutter" "$@"
