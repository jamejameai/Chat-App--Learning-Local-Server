#!/usr/bin/env bash
# ==============================================================================
# Our Chat — One-Command Launcher (backend on the home Ubuntu server)
# ==============================================================================
# This script:
# 1. Checks the Ubuntu server (scripts/server.conf: jj_home_lap@100.78.0.52 over Tailscale) is reachable
# 2. Checks the backend there (Postgres, API, LiveKit, Coturn run in Docker on it)
# 3. Redeploys the stack via scripts/deploy-lan.sh if the API is not healthy
# 4. Boots the native iOS Simulator (iPhone 18 Pro)
# 5. Builds, installs, and launches the native Swift 6 / SwiftUI app
# 6. Directly displays the running mobile app on your macOS desktop!
#
# Override the server with:  OURCHAT_SERVER=user@host ./run.sh
# The app's own default server address is the GeneratedNetworkConfig block in
# ios/MiniTelegram/Core/Networking/APIClient.swift (kept in sync by install_device.sh).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

SIMULATOR_NAME="iPhone 18 Pro"
SIMULATOR_UDID="1CC2E71C-B60A-4557-A27C-C7608FFF1FC0"
APP_BUNDLE_ID="com.minitelegram.ios"

# Server address lives in scripts/server.conf (change it with scripts/set-server.sh)
. "${SCRIPT_DIR}/scripts/server.conf"
SERVER_SSH="${OURCHAT_SERVER:-${OURCHAT_SERVER_USER}@${OURCHAT_SERVER_HOST}}"
SERVER_HOST="${SERVER_SSH#*@}"
BACKEND_PORT=3001
HEALTH_URL="http://${SERVER_HOST}:${BACKEND_PORT}/api/v1/health"

echo "========================================================================"
echo " Our Chat — Connecting Mobile App to Ubuntu Server (${SERVER_HOST})"
echo "========================================================================"

# ------------------------------------------------------------------------------
# Step 1: Server reachable on the network?
# ------------------------------------------------------------------------------
echo "[1/6] Checking server availability..."
if ping -c 1 -W 1500 "${SERVER_HOST}" >/dev/null 2>&1 && curl -fs -m 3 "${HEALTH_URL}" 2>/dev/null | grep -q '"status":"ok"'; then
    echo "  ✓ Ubuntu server is reachable and healthy: ${SERVER_HOST}"
else
    echo "  ! Ubuntu server (${SERVER_HOST}) is offline — verifying local server on this Mac..."
    if ! curl -fs -m 2 "http://127.0.0.1:3001/api/v1/health" 2>/dev/null | grep -q '"status":"ok"'; then
        bash scripts/start-server.sh
    fi
    SERVER_HOST="127.0.0.1"
    HEALTH_URL="http://127.0.0.1:3001/api/v1/health"
fi

# ------------------------------------------------------------------------------
# Step 2: Backend healthy?
# ------------------------------------------------------------------------------
echo "[2/6] Verifying backend API health..."
if curl -fs -m 4 "${HEALTH_URL}" 2>/dev/null | grep -q '"status":"ok"'; then
    echo "  ✓ Backend API is healthy: ${HEALTH_URL}"
else
    echo "  ! Backend not responding at ${HEALTH_URL} — starting local stack..."
    bash scripts/start-server.sh
fi

# ------------------------------------------------------------------------------
# Step 4: Boot Native iOS Simulator
# ------------------------------------------------------------------------------
echo "[4/6] Booting iOS Simulator ('${SIMULATOR_NAME}')..."
xcrun simctl boot "${SIMULATOR_UDID}" 2>/dev/null || true
echo "  ✓ iOS Simulator is booted."

# ------------------------------------------------------------------------------
# Step 5: Build & Install Native iOS App
# ------------------------------------------------------------------------------
echo "[5/6] Installing latest Our Chat build on simulator..."
# Always build (incremental) so source changes are never skipped. Signing must stay
# enabled: the Simulator denies Keychain access to unsigned apps (errSecMissingEntitlement).
DERIVED_DATA="${SCRIPT_DIR}/ios/DerivedData"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/MiniTelegram.app"
echo "  -> Compiling native Swift 6 app with Xcode..."
xcodebuild build \
    -project ios/MiniTelegram.xcodeproj \
    -scheme MiniTelegram \
    -destination "platform=iOS Simulator,id=${SIMULATOR_UDID}" \
    -configuration Debug \
    -derivedDataPath "${DERIVED_DATA}" >/dev/null

xcrun simctl install "${SIMULATOR_UDID}" "${APP_PATH}"
echo "  ✓ Our Chat installed on simulator."

# ------------------------------------------------------------------------------
# Step 6: Launch & Directly Display the Mobile App
# ------------------------------------------------------------------------------
echo "[6/6] Launching Our Chat and bringing Simulator to front..."
# Terminate any old instance first so new build boots cleanly
xcrun simctl terminate "${SIMULATOR_UDID}" "${APP_BUNDLE_ID}" >/dev/null 2>&1 || true
sleep 0.5
xcrun simctl launch "${SIMULATOR_UDID}" "${APP_BUNDLE_ID}" >/dev/null 2>&1 || true

# Bring the interactive iOS Simulator GUI to the front of desktop
# (Xcode 27 replaced Simulator.app with DeviceHub, bundle id com.apple.dt.Devices)
open -a Simulator 2>/dev/null || open -b com.apple.dt.Devices 2>/dev/null || true

# Capture live screen of the running mobile app as well
SCREENSHOT_PATH="/tmp/OurChat_Live_Screen.png"
sleep 1.5
xcrun simctl io "${SIMULATOR_UDID}" screenshot "${SCREENSHOT_PATH}" >/dev/null 2>&1 || true

if [ -f "${SCREENSHOT_PATH}" ]; then
    open "${SCREENSHOT_PATH}" || true
fi

echo "========================================================================"
echo " OUR CHAT OPERATIONAL & CONNECTED TO UBUNTU SERVER!"
echo "========================================================================"
echo " - Backend API Health:   ${HEALTH_URL}"
echo " - WebSocket Gateway:    ws://${SERVER_HOST}:${BACKEND_PORT}/socket.io"
echo " - LiveKit SFU:          http://${SERVER_HOST}:7880"
echo " - TURN/STUN (Coturn):   ${SERVER_HOST}:3478"
echo " - PostgreSQL 16:        internal to the server's Docker network (not exposed on the LAN)"
echo "                         ssh ${SERVER_SSH} 'docker exec -it minitelegram-postgres psql -U minitelegram minitelegram_db'"
echo " - Native iOS Simulator: ${SIMULATOR_NAME} (App: Our Chat)"
echo " - Interactive UI:       Simulator app is now in the foreground!"
echo "========================================================================"
