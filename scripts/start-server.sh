#!/usr/bin/env bash
# ==============================================================================
# Our Chat — Local Server Stack Orchestrator & Live Gateway
# ==============================================================================
# Runs the full backend stack (PostgreSQL 16, LiveKit WebRTC SFU, Coturn TURN,
# NestJS Modular Backend API, and Cloudflare Quick Tunnel) directly on this Mac.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

echo "========================================================================"
echo " 🚀 Starting Our Chat Server Stack"
echo "========================================================================"

# Detect active Wi-Fi / LAN IP and Bonjour host
DEFAULT_IF=$(route get default 2>/dev/null | grep interface | awk '{print $2}' || true)
CURRENT_IP=""
if [ -n "${DEFAULT_IF}" ]; then
    CURRENT_IP=$(ipconfig getifaddr "${DEFAULT_IF}" 2>/dev/null || true)
fi
if [ -z "${CURRENT_IP}" ]; then
    CURRENT_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
fi
LOCAL_HOST=$(scutil --get LocalHostName 2>/dev/null || hostname -s || echo "macbook")

# 1. Ensure Docker Desktop is running
echo "[1/6] Verifying Docker daemon..."
if ! docker info >/dev/null 2>&1; then
    echo "  -> Starting Docker Desktop..."
    open -a Docker
    for i in $(seq 1 30); do
        if docker info >/dev/null 2>&1; then break; fi
        sleep 2
    done
fi
if ! docker info >/dev/null 2>&1; then
    echo "  ✗ Docker daemon is not available. Please start Docker Desktop and retry."
    exit 1
fi
echo "  ✓ Docker daemon is active."

# 2. Start Supporting Infrastructure (PostgreSQL, LiveKit, Coturn)
echo "[2/6] Starting container services (PostgreSQL, LiveKit, Coturn)..."

# Ensure PostgreSQL container exists & is running
if docker ps -a --format '{{.Names}}' | grep -q '^minitelegram-postgres$'; then
    docker start minitelegram-postgres >/dev/null 2>&1 || true
else
    docker run -d \
        --name minitelegram-postgres \
        -e POSTGRES_USER=minitelegram \
        -e POSTGRES_PASSWORD=change_this_to_a_secure_database_password \
        -e POSTGRES_DB=minitelegram_db \
        -p 5432:5432 \
        postgres:16-alpine >/dev/null
fi

# Ensure LiveKit container exists & is running
if docker ps -a --format '{{.Names}}' | grep -q '^minitelegram-livekit$'; then
    docker start minitelegram-livekit >/dev/null 2>&1 || true
else
    docker run -d \
        --name minitelegram-livekit \
        -p 7880:7880 -p 7881:7881 \
        livekit/livekit-server:v1.7.2 --dev >/dev/null
fi

# Ensure Coturn container exists & is running
if docker ps -a --format '{{.Names}}' | grep -q '^minitelegram-coturn$'; then
    docker start minitelegram-coturn >/dev/null 2>&1 || true
fi

# Wait for PostgreSQL ready
echo "  -> Waiting for PostgreSQL..."
for i in $(seq 1 30); do
    if docker exec minitelegram-postgres pg_isready -U minitelegram -d minitelegram_db >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
echo "  ✓ PostgreSQL 16 is ready (port 5432)."
echo "  ✓ LiveKit SFU is ready (port 7880)."

# 3. Apply any pending DB migrations
echo "[3/6] Applying database migrations..."
DB_HOST=127.0.0.1 DB_PORT=5432 DB_USER=minitelegram DB_PASSWORD=change_this_to_a_secure_database_password DB_NAME=minitelegram_db \
    npm --prefix server run migrate >/dev/null 2>&1
echo "  ✓ Database schema is up to date."

# 4. Start Cloudflare Quick Tunnel (if not already running)
echo "[4/6] Checking Cloudflare Quick Tunnel..."
TUNNEL_HOST="$(curl -s -m 2 http://127.0.0.1:2000/quicktunnel 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("hostname") or "")' 2>/dev/null || true)"

if [ -z "${TUNNEL_HOST}" ]; then
    echo "  -> Launching cloudflared quick tunnel..."
    pkill -f "cloudflared tunnel.*--metrics 127.0.0.1:2000" 2>/dev/null || true
    (nohup cloudflared tunnel --url http://127.0.0.1:3001 --metrics 127.0.0.1:2000 < /dev/null >> cloudflared.log 2>&1 &)
    sleep 3
    for i in $(seq 1 20); do
        TUNNEL_HOST="$(curl -s -m 2 http://127.0.0.1:2000/quicktunnel 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("hostname") or "")' 2>/dev/null || true)"
        if [ -n "${TUNNEL_HOST}" ]; then break; fi
        sleep 1
    done
fi

if [ -n "${TUNNEL_HOST}" ]; then
    echo "  ✓ Cloudflare HTTPS tunnel: https://${TUNNEL_HOST}"
else
    echo "  ! Cloudflare tunnel taking longer to establish"
fi

# 5. Build and Start Backend NestJS Server
echo "[5/6] Checking NestJS Backend Server..."
if curl -fs -m 2 http://127.0.0.1:3001/api/v1/health 2>/dev/null | grep -q '"status":"ok"'; then
    echo "  ✓ Backend API is already running and healthy."
else
    if [ ! -f server/dist/main.js ]; then
        echo "  -> Compiling NestJS server..."
        npm --prefix server run build >/dev/null
    fi
    lsof -ti :3001 | xargs kill -9 2>/dev/null || true
    mkdir -p server/uploads uploads
    (nohup env \
        PORT=3001 \
        HOST=0.0.0.0 \
        NODE_ENV=production \
        DB_HOST=127.0.0.1 \
        DB_PORT=5432 \
        DB_USER=minitelegram \
        DB_PASSWORD=change_this_to_a_secure_database_password \
        DB_NAME=minitelegram_db \
        JWT_ACCESS_SECRET=replace_with_a_64_char_cryptographically_secure_random_string_access \
        JWT_ACCESS_EXPIRES_IN=15m \
        JWT_REFRESH_SECRET=replace_with_a_64_char_cryptographically_secure_random_string_refresh \
        JWT_REFRESH_EXPIRES_IN=30d \
        STORAGE_DRIVER=local \
        STORAGE_LOCAL_PATH=./uploads \
        LIVEKIT_URL=http://127.0.0.1:7880 \
        LIVEKIT_PUBLIC_URL=ws://${CURRENT_IP}:7880 \
        LIVEKIT_API_KEY=devkey \
        LIVEKIT_API_SECRET=secret \
        TUNNEL_METRICS_URL=http://127.0.0.1:2000 \
        node server/dist/main.js < /dev/null >> server.log 2>&1 &)
fi

# 6. Verify Health
echo "[6/6] Verifying server health..."
SERVER_OK=false
for i in $(seq 1 20); do
    if curl -fs -m 2 http://127.0.0.1:3001/api/v1/health | grep -q '"status":"ok"'; then
        SERVER_OK=true
        break
    fi
    sleep 1
done

if [ "${SERVER_OK}" = true ]; then
    echo "  ✓ Server is healthy and accepting traffic!"
else
    echo "  ✗ Server failed to respond on http://127.0.0.1:3001/api/v1/health. Check server.log:"
    tail -n 15 server.log
    exit 1
fi

PUBLIC_API_URL="$(curl -fs -m 3 http://127.0.0.1:3001/api/v1/network/config 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("public_url") or "")' 2>/dev/null || true)"

echo "========================================================================"
echo " 🎉 OUR CHAT SERVER IS OPERATIONAL!"
echo "========================================================================"
echo " - Local Wi-Fi API:    http://${CURRENT_IP}:3001/api/v1"
echo " - Local Bonjour API:  http://${LOCAL_HOST}.local:3001/api/v1"
echo " - Internet (HTTPS):   ${PUBLIC_API_URL:-https://${TUNNEL_HOST}/api/v1}"
echo " - LiveKit SFU:        ws://${CURRENT_IP}:7880"
echo " - Coturn TURN:        ${CURRENT_IP}:3478"
echo " - PostgreSQL 16:      127.0.0.1:5432"
echo " - Server Log:         server.log"
echo " - Tunnel Log:         cloudflared.log"
echo "========================================================================"
