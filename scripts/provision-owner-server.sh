#!/usr/bin/env bash
set -euo pipefail
exec 9>/var/lock/joba-deployment.lock
flock -n 9
cd /opt/joba/current
test "$(git rev-parse HEAD)" = "${1:?Expected server commit required}"
args=(--env-file /etc/joba/production.env -f infra/production/compose.yaml)
docker compose "${args[@]}" cp /tmp/provision-owner-login.cjs api:/tmp/joba-provision-owner.cjs >/dev/null
docker compose "${args[@]}" cp /tmp/admin-delivery-public.pem api:/tmp/joba-admin-public.pem >/dev/null
docker compose "${args[@]}" exec -T -u root api chmod 0644 /tmp/joba-provision-owner.cjs /tmp/joba-admin-public.pem
docker compose "${args[@]}" exec -T -e JOBA_OWNER_PASSWORD_LOGIN=owner-authorized api node /tmp/joba-provision-owner.cjs
