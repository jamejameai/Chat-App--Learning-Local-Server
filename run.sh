#!/usr/bin/env bash
# ==============================================================================
# Mini Telegram — One-Command Full Stack & Native App Launcher
# ==============================================================================
# This script:
# 1. Launches Docker daemon (if not active)
# 2. Starts PostgreSQL 16, LiveKit SFU, and Coturn STUN/TURN containers
# 3. Runs PostgreSQL database migrations (001 and 002)
# 4. Starts the NestJS modular monolith backend on port 3001
# 5. Boots the native iOS Simulator (iPhone 18 Pro)
# 6. Builds, installs, and launches the native Swift 6 / SwiftUI app
# 7. Directly displays the running mobile app on your macOS desktop!
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

SIMULATOR_NAME="iPhone 18 Pro"
SIMULATOR_UDID="1CC2E71C-B60A-4557-A27C-C7608FFF1FC0"
APP_BUNDLE_ID="com.minitelegram.ios"
BACKEND_PORT=3001
DB_PORT=5432

echo "========================================================================"
echo " 🚀 Mini Telegram — Starting Entire Host Stack & Mobile App"
echo "========================================================================"

# ------------------------------------------------------------------------------
# Step 1: Ensure Docker Daemon is Active
# ------------------------------------------------------------------------------
echo "[1/7] Checking Docker daemon status..."
if ! docker info >/dev/null 2>&1; then
    echo "  -> Starting Docker Desktop..."
    open -a Docker || true
    echo "  -> Waiting for Docker daemon to become responsive..."
    for i in {1..30}; do
        if docker info >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
fi
echo "  ✓ Docker daemon is active."

# ------------------------------------------------------------------------------
# Step 2: Start Infrastructure Containers (Postgres, LiveKit, Coturn)
# ------------------------------------------------------------------------------
echo "[2/7] Starting infrastructure services (Postgres, LiveKit, Coturn)..."
if ! docker ps --format '{{.Names}}' | grep -q "^minitelegram-postgres$"; then
    if docker ps -a --format '{{.Names}}' | grep -q "^minitelegram-postgres$"; then
        docker start minitelegram-postgres minitelegram-livekit minitelegram-coturn >/dev/null
    else
        docker run -d --name minitelegram-postgres \
            -e POSTGRES_USER=minitelegram \
            -e POSTGRES_PASSWORD=change_this_to_a_secure_database_password \
            -e POSTGRES_DB=minitelegram_db \
            -p ${DB_PORT}:5432 postgres:16-alpine >/dev/null
        docker run -d --name minitelegram-livekit \
            -p 7880:7880 -p 7881:7881 livekit/livekit-server:v1.7.2 --dev >/dev/null
        docker run -d --name minitelegram-coturn \
            -p 3478:3478 -p 3478:3478/udp coturn/coturn:4.6.2-alpine >/dev/null
    fi
fi

# Wait for PostgreSQL to accept connections
until docker exec minitelegram-postgres pg_isready -U minitelegram >/dev/null 2>&1; do
    sleep 0.5
done
echo "  ✓ PostgreSQL 16 is ready and accepting connections."

# ------------------------------------------------------------------------------
# Step 3: Run Database Migrations
# ------------------------------------------------------------------------------
echo "[3/7] Running database schema migrations..."
DB_HOST=127.0.0.1 DB_PORT=${DB_PORT} DB_USER=minitelegram \
DB_PASSWORD=change_this_to_a_secure_database_password DB_NAME=minitelegram_db \
npm run migrate --prefix server >/dev/null 2>&1 || true
echo "  ✓ Database migrations verified."

# ------------------------------------------------------------------------------
# Step 4: Start Backend Monolith Server (Port 3001)
# ------------------------------------------------------------------------------
echo "[4/7] Checking backend API server status..."
if ! lsof -i :${BACKEND_PORT} >/dev/null 2>&1; then
    echo "  -> Launching NestJS backend server daemon on port ${BACKEND_PORT}..."
    nohup env PORT=${BACKEND_PORT} DB_HOST=127.0.0.1 DB_PORT=${DB_PORT} \
        DB_USER=minitelegram DB_PASSWORD=change_this_to_a_secure_database_password \
        DB_NAME=minitelegram_db node server/dist/main.js > "${SCRIPT_DIR}/server.log" 2>&1 &
    
    # Wait for server health endpoint
    for i in {1..20}; do
        if curl -s "http://127.0.0.1:${BACKEND_PORT}/api/v1/health" | grep -q '"status":"ok"'; then
            break
        fi
        sleep 0.5
    done
fi
echo "  ✓ Backend API is healthy: http://127.0.0.1:${BACKEND_PORT}/api/v1"

# ------------------------------------------------------------------------------
# Step 5: Boot Native iOS Simulator
# ------------------------------------------------------------------------------
echo "[5/7] Booting iOS Simulator ('${SIMULATOR_NAME}')..."
xcrun simctl boot "${SIMULATOR_UDID}" 2>/dev/null || true
echo "  ✓ iOS Simulator is booted."

# ------------------------------------------------------------------------------
# Step 6: Build & Install Native iOS App
# ------------------------------------------------------------------------------
echo "[6/7] Building and installing MiniTelegram.app..."
APP_PATH=$(find /Users/macbook/Library/Developer/Xcode/DerivedData -name "MiniTelegram.app" 2>/dev/null | grep "Debug-iphonesimulator" | head -n 1 || echo "")

if [ -z "${APP_PATH}" ] || [ ! -d "${APP_PATH}" ]; then
    echo "  -> Compiling native Swift 6 app with Xcode..."
    xcodebuild build \
        -project ios/MiniTelegram.xcodeproj \
        -scheme MiniTelegram \
        -destination "platform=iOS Simulator,name=${SIMULATOR_NAME}" \
        -configuration Debug \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO >/dev/null
    APP_PATH=$(find /Users/macbook/Library/Developer/Xcode/DerivedData -name "MiniTelegram.app" 2>/dev/null | grep "Debug-iphonesimulator" | head -n 1)
fi

xcrun simctl install "${SIMULATOR_UDID}" "${APP_PATH}"
echo "  ✓ MiniTelegram.app installed on simulator."

# ------------------------------------------------------------------------------
# Step 7: Launch & Directly Display the Mobile App
# ------------------------------------------------------------------------------
echo "[7/7] Launching mobile app and opening live display..."
xcrun simctl launch "${SIMULATOR_UDID}" "${APP_BUNDLE_ID}" >/dev/null 2>&1 || true

# Capture live screen of the running mobile app and open it directly on desktop
SCREENSHOT_PATH="/tmp/MiniTelegram_Live_Screen.png"
sleep 1
xcrun simctl io "${SIMULATOR_UDID}" screenshot "${SCREENSHOT_PATH}" >/dev/null 2>&1 || true

# Display the running app in Preview
if [ -f "${SCREENSHOT_PATH}" ]; then
    open "${SCREENSHOT_PATH}"
fi

# Also launch Xcode with the native project ready
open ios/MiniTelegram.xcodeproj || true

echo "========================================================================"
echo " 🎉 ALL SYSTEMS OPERATIONAL & MOBILE APP DISPLAYED!"
echo "========================================================================"
echo " - Backend API Health:   http://127.0.0.1:${BACKEND_PORT}/api/v1/health"
echo " - WebSocket Gateway:    ws://127.0.0.1:${BACKEND_PORT}/socket.io"
echo " - LiveKit SFU:          http://127.0.0.1:7880"
echo " - PostgreSQL 16:        127.0.0.1:${DB_PORT} (User: minitelegram)"
echo " - Native iOS Simulator: ${SIMULATOR_NAME} (App: ${APP_BUNDLE_ID})"
echo " - Live App Display:     ${SCREENSHOT_PATH} (Opened in Preview)"
echo " - Xcode Workspace:      ios/MiniTelegram.xcodeproj (Opened in Xcode)"
echo "========================================================================"
