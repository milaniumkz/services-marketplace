#!/usr/bin/env bash
set -euo pipefail
joba_commit="${1:?Exact source commit required}"
[[ "$joba_commit" =~ ^[0-9a-f]{40}$ ]] || exit 2
exec 9>/var/lock/joba-deployment.lock
flock -n 9
joba_source="/opt/joba/mobile-releases/$joba_commit"
mkdir -p "$joba_source" /var/backups/joba/mobile
chmod 700 /var/backups/joba/mobile
if [[ ! -d "$joba_source/.git" ]]; then
 git init -q "$joba_source"
 git -C "$joba_source" remote add origin https://github.com/milaniumkz/services-marketplace.git
 git -C "$joba_source" fetch --update-shallow --no-tags /opt/joba/current HEAD
fi
git -C "$joba_source" fetch --depth=1 origin "$joba_commit"
git -C "$joba_source" checkout --detach FETCH_HEAD
test "$(git -C "$joba_source" rev-parse HEAD)" = "$joba_commit"
joba_previous=(docker compose --env-file /etc/joba/production.env -f /opt/joba/current/infra/production/compose.yaml)
joba_compose=(docker compose --env-file /etc/joba/production.env -f "$joba_source/infra/production/compose.yaml")
joba_old_image="$(docker inspect --format '{{.Image}}' "$("${joba_previous[@]}" ps -q api)")"
umask 077
"${joba_previous[@]}" exec -T database pg_dump -U joba joba > "/var/backups/joba/mobile/$joba_commit.sql"
"${joba_compose[@]}" build api
rollback(){ docker tag "$joba_old_image" joba-api:latest; "${joba_previous[@]}" up -d --no-deps --no-build api; }
trap rollback ERR
"${joba_compose[@]}" up -d --no-deps --no-build api
for joba_attempt in $(seq 1 60); do
 if curl --max-time 10 -fsS https://joba.com.kz/api/v1/public/mobile-release | python3 -c 'import json,sys; assert json.load(sys.stdin)["data"]["free_core_access"] is True' 2>/dev/null; then break; fi
 sleep 2
done
curl --max-time 10 -fsS https://joba.com.kz/api/v1/public/mobile-release | python3 -c 'import json,sys; assert json.load(sys.stdin)["data"]["free_core_access"] is True'
"${joba_compose[@]}" cp "$joba_source/scripts/provision-store-review.cjs" api:/tmp/joba-provision-store-review.cjs
"${joba_compose[@]}" cp "$joba_source/infra/production/store-review-recipient.pem" api:/tmp/joba-store-review-recipient.pem
"${joba_compose[@]}" exec -T -u root api chmod 0644 /tmp/joba-provision-store-review.cjs /tmp/joba-store-review-recipient.pem
"${joba_compose[@]}" exec -T -e JOBA_STORE_REVIEW_AUTHORIZATION=owner-authorized api node /tmp/joba-provision-store-review.cjs > /tmp/joba-store-review-envelope.b64
printf '%s\n' "$joba_commit" > /etc/joba/mobile-api-release
trap - ERR
printf '%s\n' 'Free mobile core API deployed and review credentials encrypted. Existing web assets were preserved.'
