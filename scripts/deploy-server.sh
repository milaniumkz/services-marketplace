#!/usr/bin/env bash
# Executed over verified SSH by the authorized deployment workflow.
set -euo pipefail
umask 077
joba_commit="${1:?Commit required}"
joba_archive="${2:?Frontend archive required}"
joba_domain="${3:?Domain required}"
joba_expected_ip="${4:-188.241.217.228}"
[[ "$joba_commit" =~ ^[0-9a-f]{40}$ && "$joba_domain" =~ ^[a-zA-Z0-9.-]+$ ]] || exit 2
[[ "$EUID" == 0 ]] || { echo 'Initial server provisioning requires root' >&2; exit 1; }
python3 - "$joba_domain" "$joba_expected_ip" <<'PYDNS'
import socket,sys
addresses={x[4][0] for x in socket.getaddrinfo(sys.argv[1],443,type=socket.SOCK_STREAM)}
assert sys.argv[2] in addresses, 'Public DNS must point to the supplied server before certificate issuance'
PYDNS
exec 9>/var/lock/joba-deployment.lock
flock -n 9 || { echo 'Another deployment is running' >&2; exit 75; }
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  . /etc/os-release
  [[ "$ID" == ubuntu || "$ID" == debian ]] || { echo 'Docker provisioning supports Ubuntu/Debian only' >&2; exit 1; }
  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg git python3
  mkdir -p /etc/apt/keyrings
  joba_key="$(mktemp)"
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o "$joba_key"
  [[ "$(gpg --show-keys --with-colons "$joba_key" | awk -F: '$1=="fpr" {print $10; exit}')" == 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 ]] || { echo 'Docker signing key mismatch' >&2; exit 1; }
  gpg --batch --yes --dearmor -o /etc/apt/keyrings/joba-docker.gpg "$joba_key"
  chmod 644 /etc/apt/keyrings/joba-docker.gpg
  rm -f "$joba_key"
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/joba-docker.gpg] https://download.docker.com/linux/%s %s stable\n' "$(dpkg --print-architecture)" "$ID" "$VERSION_CODENAME" > /etc/apt/sources.list.d/joba-docker.list
  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
command -v git >/dev/null
command -v python3 >/dev/null
systemctl enable --now docker
[[ "$(df -Pk /opt | awk 'NR==2 {print $4}')" -ge 4194304 ]] || { echo 'At least 4 GiB free disk is required' >&2; exit 1; }
mkdir -p /etc/joba /opt/joba/releases /var/backups/joba
chmod 700 /etc/joba /var/backups/joba
joba_release="/opt/joba/releases/$joba_commit"
mkdir -p "$joba_release"
if [[ ! -d "$joba_release/source/.git" ]]; then
  git init -q "$joba_release/source"
  git -C "$joba_release/source" remote add origin https://github.com/milaniumkz/services-marketplace.git
  git -C "$joba_release/source" fetch --depth=1 origin "$joba_commit"
  git -C "$joba_release/source" checkout --detach FETCH_HEAD
fi
[[ "$(git -C "$joba_release/source" rev-parse HEAD)" == "$joba_commit" ]] || exit 1
[[ -z "$(git -C "$joba_release/source" status --porcelain --untracked-files=no)" ]] || { echo 'Release source was modified; refusing overwrite' >&2; exit 1; }
mkdir -p "$joba_release/source/release"
python3 - "$joba_archive" "$joba_release/source/release" <<'PYTAR'
import shutil,sys,tarfile
from pathlib import Path,PurePosixPath
root=Path(sys.argv[2])
with tarfile.open(sys.argv[1],'r:gz') as archive:
    for member in archive:
        name=PurePosixPath(member.name)
        assert not name.is_absolute() and '..' not in name.parts and name.parts[0]=='web', 'Invalid archive path'
        assert member.isdir() or member.isfile(), 'Archive links are not permitted'
        target=root.joinpath(*name.parts)
        if member.isdir():target.mkdir(parents=True,exist_ok=True)
        else:
            target.parent.mkdir(parents=True,exist_ok=True)
            with archive.extractfile(member) as source,target.open('wb') as output:shutil.copyfileobj(source,output)
PYTAR
python3 - "$joba_release/source/release/web" "$joba_commit" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);manifest=json.loads((root/'release.json').read_text())
assert manifest['commit']==sys.argv[2], 'Frontend commit differs from source'
for name,digest in manifest['files'].items():
    p=(root/name).resolve();assert p.is_relative_to(root.resolve()), 'Invalid release path'
    assert hashlib.sha256(p.read_bytes()).hexdigest()==digest, 'Frontend checksum mismatch: '+name
PY
if [[ ! -f /etc/joba/production.env ]]; then
  python3 - "$joba_domain" <<'PY'
import os,secrets,sys
fd=os.open('/etc/joba/production.env',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f:f.write('JOBA_DOMAIN='+sys.argv[1]+'\nJOBA_DATABASE_PASSWORD='+secrets.token_hex(32)+'\nJOBA_FILE_KEY='+secrets.token_hex(32)+'\n')
PY
fi
# Existing keys and passwords must survive redeployment; never regenerate them.
grep -qx "JOBA_DOMAIN=$joba_domain" /etc/joba/production.env || { echo 'Configured domain differs; inspect server configuration' >&2; exit 1; }
cd "$joba_release/source"
joba_compose=(docker compose --env-file /etc/joba/production.env -f infra/production/compose.yaml)
"${joba_compose[@]}" config --quiet
if [[ -n "$("${joba_compose[@]}" ps -q database)" ]]; then
  joba_backup="/var/backups/joba/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$joba_backup"
  "${joba_compose[@]}" exec -T database pg_dump -U joba -d joba > "$joba_backup/database.sql"
  "${joba_compose[@]}" exec -T -u root api tar -C /app/.local -czf - private-files > "$joba_backup/private-files.tar.gz"
  cp /etc/joba/production.env "$joba_backup/production.env"
fi
"${joba_compose[@]}" up -d --build --wait --wait-timeout 300
# User explicitly authorized these initial documents with blank operator details.
# Existing legal versions are preserved on every subsequent deployment.
"${joba_compose[@]}" cp scripts/publish-initial-kz-legal.cjs api:/tmp/joba-publish-legal.cjs
python3 - <<'PYLEGAL' | "${joba_compose[@]}" exec -T -e JOBA_INITIAL_KZ_LEGAL=owner-authorized-2026-10-15 -e JOBA_LEGAL_STORE_MODULE=/app/services/api/dist/store api node /tmp/joba-publish-legal.cjs
import json
from pathlib import Path
print(json.dumps([{'type':kind,'locale':'ru','content':Path('docs/legal/kz/'+name+'.ru.txt').read_text()} for kind,name in [('terms','terms'),('privacy','privacy')]]))
PYLEGAL
# This verifies a trusted public certificate; no -k/self-signed fallback.
curl --fail --silent --show-error --retry 20 --retry-delay 5 --retry-all-errors --max-time 15 "https://$joba_domain/health"
curl --fail --silent --show-error --max-time 15 "https://$joba_domain/" -o /dev/null
curl --fail --silent --show-error --max-time 15 "https://$joba_domain/admin/" -o /dev/null
ln -sfn "$joba_release/source" /opt/joba/current
printf '\nVerified deployment: https://%s/ commit %s\n' "$joba_domain" "$joba_commit"
