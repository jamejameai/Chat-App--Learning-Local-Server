#!/usr/bin/env bash
# ==============================================================================
# Deploy Our Chat Directly to Connected Physical iPhone
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

APP_BUNDLE_ID="com.minitelegram.ios"
TEAM_ID="XRW2MT8W59"

echo "========================================================================"
echo " 📱 Deploying Our Chat to Physical iPhone"
echo "========================================================================"

echo "[1/4] Detecting connected iOS device..."
DEVICE_UDID=$(xcrun devicectl list devices | grep "physical" | awk '{print $2}' | tr -d '()' | head -n 1 || true)

if [ -z "${DEVICE_UDID}" ]; then
    DEVICE_UDID="00008101-000964CC3C44001E"
fi

echo "  ✓ Target device: ${DEVICE_UDID}"

echo "[2/4] Building ARM64 native app with Xcode..."
xcodebuild build \
    -project ios/MiniTelegram.xcodeproj \
    -scheme MiniTelegram \
    -destination "platform=iOS,id=${DEVICE_UDID}" \
    -configuration Debug \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_STYLE=Automatic \
    "CODE_SIGN_IDENTITY=Apple Development" \
    -allowProvisioningUpdates >/dev/null

DERIVED_DATA_PATH=$(xcodebuild -project ios/MiniTelegram.xcodeproj -scheme MiniTelegram -showBuildSettings | grep -m 1 "TARGET_BUILD_DIR =" | awk '{print $3}')
APP_PATH="${DERIVED_DATA_PATH}/MiniTelegram.app"

echo "  ✓ Build successful: ${APP_PATH}"

echo "[3/4] Installing app on physical device..."
xcrun devicectl device install app --device "${DEVICE_UDID}" "${APP_PATH}"
echo "  ✓ App installed on device."

echo "[4/4] Launching Our Chat on phone..."
xcrun devicectl device process launch --terminate-existing --device "${DEVICE_UDID}" "${APP_BUNDLE_ID}" 2>/dev/null || echo "  (Ensure iPhone screen is unlocked to auto-launch)"

echo "========================================================================"
echo " 🎉 OUR CHAT DEPLOYED TO IPHONE!"
echo "========================================================================"
