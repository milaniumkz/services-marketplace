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
bash scripts/flutter-mobile.sh build web --release --no-web-resources-cdn --dart-define="JOBA_KZ_API_URL=https://$joba_domain"
mkdir -p release/web/{mobile,admin,site}
cp -a apps/mobile/build/web/. release/web/mobile/
cp -a apps/admin/dist/. release/web/admin/
cp -a apps/web/dist/. release/web/site/
# Remove previous build files by building in a clean CI workspace; never include local data.
python3 - <<'PY'
import hashlib,json,subprocess
from pathlib import Path
root=Path('release/web');files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file() and p.name!='release.json'}
(root/'release.json').write_text(json.dumps({'commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'files':files},indent=2)+'\n')
PY
