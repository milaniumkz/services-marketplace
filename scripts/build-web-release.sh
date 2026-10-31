#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
joba_domain="${JOBA_DOMAIN:-188-241-217-228.sslip.io}"
[[ "$joba_domain" =~ ^[a-zA-Z0-9.-]+$ && "$joba_domain" == *.* ]] || { echo 'Set a public DNS hostname in JOBA_DOMAIN' >&2; exit 1; }
joba_flutter="${FLUTTER_ROOT:-/workspace/flutter-sdk}/bin/flutter"
[[ -x "$joba_flutter" ]] || { echo 'Set FLUTTER_ROOT to Flutter 3.35.7' >&2; exit 1; }
npm run build --workspace @marketplace/admin -- --base=/admin/
npm run build --workspace @marketplace/web -- --base=/site/
bash scripts/flutter-mobile.sh pub get --enforce-lockfile
bash scripts/flutter-mobile.sh build web --release --pwa-strategy=none --no-web-resources-cdn --dart-define=JOBA_WEB_SAME_ORIGIN=true --dart-define="JOBA_API_URL=https://$joba_domain"
mkdir -p release/web/{mobile,admin,site}
cp -a apps/mobile/build/web/. release/web/mobile/
# Keep the owner supplied seller declaration at the public domain root.
cp apps/mobile/web/app-ads.txt release/web/mobile/app-ads.txt
cp apps/mobile/web/ads.txt release/web/mobile/ads.txt
cp apps/mobile/web/robots.txt release/web/mobile/robots.txt
cp apps/mobile/web/sitemap.xml release/web/mobile/sitemap.xml
cp -a apps/admin/dist/. release/web/admin/
cp -a apps/web/dist/. release/web/site/
# Remove previous build files by building in a clean CI workspace; never include local data.
python3 - <<'PY'
import hashlib,json,subprocess
from pathlib import Path
root=Path('release/web')
commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
# Both entry points change URL on each release, bypassing old browser caches.
index=root/'mobile/index.html'
index.write_text(index.read_text().replace('joba_release=20261015-worker-retirement','joba_release='+commit).replace('src="joba-web-ads.js"','src="joba-web-ads.js?joba_release='+commit+'"'))
bootstrap=root/'mobile/flutter_bootstrap.js'
source=bootstrap.read_text()
assert '"mainJsPath":"main.dart.js"' in source, 'Flutter entrypoint configuration changed'
bootstrap.write_text(source.replace('"mainJsPath":"main.dart.js"','"mainJsPath":"main.dart.js?joba_release='+commit+'"'))
files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file() and p.name!='release.json'}
(root/'release.json').write_text(json.dumps({'commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'files':files},indent=2)+'\n')
PY
