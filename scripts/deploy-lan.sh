#!/usr/bin/env bash
# ==============================================================================
# Our Chat — deploy the full backend stack to the home Ubuntu server over SSH.
#
#   bash scripts/deploy-lan.sh                # sync code, (re)build, migrate, health-check
#   bash scripts/deploy-lan.sh --import-local # also copy the local Docker database's data
#
# Requires: SSH key login to the server, Docker + Compose installed there.
# Secrets are generated on the server on first run and kept in infrastructure/.env
# (mode 600) — they never touch this repository.
# ==============================================================================
set -euo pipefail

# Server address lives in scripts/server.conf (change it with scripts/set-server.sh)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/server.conf"
REMOTE="${REMOTE:-${OURCHAT_SERVER_USER}@${OURCHAT_SERVER_HOST}}"
HOST_IP="${HOST_IP:-${REMOTE#*@}}"
REMOTE_DIR="${REMOTE_DIR:-our-chat}"   # relative to the remote home directory
API_PORT=3001
COMPOSE="docker compose -f infrastructure/docker-compose.lan.yml --env-file infrastructure/.env"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "${REMOTE}")

echo "[1/5] Checking SSH + Docker on ${REMOTE}..."
"${SSH[@]}" 'docker compose version >/dev/null' \
    || { echo "  ✗ Cannot run 'docker compose' on ${REMOTE} (is the SSH key loaded? ssh-add -l)"; exit 1; }

echo "[2/5] Syncing server/ and infrastructure/ to ~/${REMOTE_DIR}..."
# downloads/ (OurChat.ipa) must exist before Docker mounts it, or Docker creates it owned by root
"${SSH[@]}" "mkdir -p ${REMOTE_DIR}/downloads"
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -czf - -C "${ROOT}" \
    --exclude node_modules --exclude dist --exclude uploads --exclude '*.log' --exclude .DS_Store \
    --exclude 'infrastructure/.env' --exclude 'infrastructure/*.lan.yaml' --exclude 'infrastructure/coturn/*.lan.conf' \
    server infrastructure \
  | "${SSH[@]}" "tar xzf - -C ${REMOTE_DIR}"

# The app file for the download page (anyone installs it with their own Apple ID)
if [ -f "${ROOT}/dist/OurChat.ipa" ]; then
    bash "${ROOT}/scripts/publish-ipa.sh" || echo "  ! OurChat.ipa not uploaded (download page keeps the old file)"
fi

echo "[3/5] Generating secrets on the server (first run only)..."
"${SSH[@]}" "HOST_IP='${HOST_IP}' API_PORT='${API_PORT}' PUBLIC_BASE='${OURCHAT_PUBLIC_URL:-}' bash -s" "${REMOTE_DIR}" <<'REMOTE_SCRIPT'
set -euo pipefail
cd "$1/infrastructure"
rnd() { openssl rand -hex 32; }

if [ ! -f .env ]; then
    umask 077
    cat > .env <<EOF
DB_USER=minitelegram
DB_NAME=minitelegram_db
DB_PASSWORD=$(rnd)
JWT_ACCESS_SECRET=$(rnd)
JWT_REFRESH_SECRET=$(rnd)
LIVEKIT_API_KEY=ourchat
LIVEKIT_API_SECRET=$(rnd)
TURN_SECRET=$(rnd)
PUBLIC_URL=http://${HOST_IP}:${API_PORT}
EOF
    echo "  ✓ created infrastructure/.env"
else
    echo "  ✓ infrastructure/.env already exists (kept)"
fi

# The server's address follows the Wi-Fi: keep PUBLIC_URL in step on every deploy
sed -i "s|^PUBLIC_URL=.*|PUBLIC_URL=http://${HOST_IP}:${API_PORT}|" .env
# Fixed internet address (Tailscale Funnel) the server hands to the app
sed -i '/^PUBLIC_API_URL=/d' .env
if [ -n "${PUBLIC_BASE}" ]; then
    echo "PUBLIC_API_URL=${PUBLIC_BASE}/api/v1" >> .env
fi
# Calls: phones connect to LiveKit on the server's address
if grep -q '^LIVEKIT_PUBLIC_URL=' .env; then
    sed -i "s|^LIVEKIT_PUBLIC_URL=.*|LIVEKIT_PUBLIC_URL=ws://${HOST_IP}:7880|" .env
else
    echo "LIVEKIT_PUBLIC_URL=ws://${HOST_IP}:7880" >> .env
fi

set -a; . ./.env; set +a
umask 022
# Remember the current call-server config, to restart LiveKit/Coturn only if it changes (e.g. new IP)
CONFIG_BEFORE="$(cat livekit.lan.yaml coturn/turnserver.lan.conf 2>/dev/null | md5sum)"
cat > livekit.lan.yaml <<EOF
port: 7880
bind_addresses:
  - ""
rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 50050
  use_external_ip: false
  node_ip: ${HOST_IP}
keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}
logging:
  level: info
EOF
sed -e "s|^static-auth-secret=.*|static-auth-secret=${TURN_SECRET}|" \
    -e "s|^realm=.*|realm=${HOST_IP}|" \
    coturn/turnserver.conf > coturn/turnserver.lan.conf
echo "external-ip=${HOST_IP}" >> coturn/turnserver.lan.conf
if [ "$(cat livekit.lan.yaml coturn/turnserver.lan.conf | md5sum)" != "${CONFIG_BEFORE}" ]; then
    touch .call-config-changed
fi
REMOTE_SCRIPT

echo "[4/5] Building and starting containers (first build takes a few minutes)..."
"${SSH[@]}" "cd ${REMOTE_DIR} && ${COMPOSE} up -d --build" 2>&1 | tail -15
# LiveKit/Coturn only read their config at start: restart them when it changed (new IP)
"${SSH[@]}" "cd ${REMOTE_DIR} && if [ -f infrastructure/.call-config-changed ]; then ${COMPOSE} restart livekit coturn && rm -f infrastructure/.call-config-changed && echo '  ✓ Call servers restarted with the new address'; fi"

echo "  -> Applying database migrations..."
"${SSH[@]}" "cd ${REMOTE_DIR} && for i in \$(seq 1 30); do ${COMPOSE} exec -T backend node dist/database/migrate.js && exit 0; sleep 2; done; exit 1" 2>&1 | tail -8

if [ "${1:-}" = "--import-local" ]; then
    echo "  -> Importing data from the local Docker database (existing rows are kept)..."
    docker exec minitelegram-postgres pg_dump -U minitelegram -d minitelegram_db \
        --data-only --inserts --on-conflict-do-nothing --disable-triggers \
        --exclude-table=schema_migrations \
      | "${SSH[@]}" "cd ${REMOTE_DIR} && ${COMPOSE} exec -T postgres psql -q -v ON_ERROR_STOP=1 -U minitelegram -d minitelegram_db" >/dev/null
    echo "  ✓ local data imported"
fi

echo "[5/5] Health check from this Mac..."
for i in $(seq 1 30); do
    if curl -fs -m 3 "http://${HOST_IP}:${API_PORT}/api/v1/health" | grep -q '"status":"ok"'; then
        echo "  ✓ http://${HOST_IP}:${API_PORT}/api/v1/health is OK"
        echo "  -> Waiting for the internet tunnel address..."
        for j in $(seq 1 20); do
            PUBLIC_URL="$(curl -fs -m 3 "http://${HOST_IP}:${API_PORT}/api/v1/network/config" \
                | python3 -c 'import sys,json; print(json.load(sys.stdin).get("public_url") or "")' 2>/dev/null || true)"
            [ -n "${PUBLIC_URL}" ] && break
            sleep 2
        done
        if [ -n "${PUBLIC_URL:-}" ]; then
            echo "  ✓ Internet address: ${PUBLIC_URL}"
        else
            echo "  ! Tunnel address not available yet — check: docker logs minitelegram-tunnel"
        fi
        exit 0
    fi
    sleep 2
done
echo "  ✗ Backend not reachable from this Mac at http://${HOST_IP}:${API_PORT} — check 'docker compose logs backend' and the server firewall (ufw)."
exit 1
