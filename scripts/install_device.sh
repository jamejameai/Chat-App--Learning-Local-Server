#!/usr/bin/env bash
# ==============================================================================
# Our Chat — Multi-Device iOS Installer & Network Auto-Configurator
# ==============================================================================
# Seamlessly installs Our Chat onto any iPhone (same or different Apple ID,
# and automatically adapts to any new Wi-Fi network / IP address tomorrow).
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

APP_BUNDLE_ID="com.minitelegram.ios"
DEFAULT_TEAM_ID="XRW2MT8W59"
TEAM_ID="${DEVELOPMENT_TEAM:-$DEFAULT_TEAM_ID}"
DEVICE_UDID=""
PACKAGE_ONLY=false
SERVE_ONLY=false
LIST_ONLY=false

# ------------------------------------------------------------------------------
# Help Documentation
# ------------------------------------------------------------------------------
show_help() {
    cat <<EOF
Usage: ./scripts/install_device.sh [OPTIONS]

Install Our Chat to any iPhone (different Apple ID, different Wi-Fi network/IP).

OPTIONS:
  -d, --device <UDID>     Target iPhone UDID or identifier
  -t, --team <TEAM_ID>    Apple Developer Team ID (default: ${DEFAULT_TEAM_ID})
  -p, --package-ipa       Build and package dist/OurChat.ipa without installing
  -s, --serve             Show public download link & active Cloudflare tunnel
  -l, --list              List all connected physical iPhones
  -h, --help              Show this help message

WORKFLOW FOR TOMORROW:
  1. Connect your Mac to the new Wi-Fi network.
  2. Plug the second iPhone into your Mac using a USB cable.
  3. Unlock the iPhone screen and tap "Trust This Computer" if prompted.
  4. Run:
       ./scripts/install_device.sh
  5. The script automatically:
     - Detects the Mac's new Wi-Fi IP and Bonjour hostname
     - Injects the new network address into the iOS app
     - Checks and starts backend and database services
     - Registers the second iPhone's UDID with Apple Developer
     - Compiles, signs, installs, and launches the app on the phone!

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Parse Arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--device)
            DEVICE_UDID="$2"
            shift 2
            ;;
        -t|--team)
            TEAM_ID="$2"
            shift 2
            ;;
        -p|--package-ipa)
            PACKAGE_ONLY=true
            shift
            ;;
        -s|--serve)
            SERVE_ONLY=true
            shift
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

echo "========================================================================"
echo " 📱 Our Chat — Multi-Device Installer & Network Adapter"
echo "========================================================================"

# ------------------------------------------------------------------------------
# Step 1: Detect Network & Adapt Configuration
# ------------------------------------------------------------------------------
echo "[1/5] Detecting current Wi-Fi network & IP address..."

# Detect active Wi-Fi / default interface IP
DEFAULT_IF=$(route get default 2>/dev/null | grep interface | awk '{print $2}' || true)
CURRENT_IP=""
if [ -n "${DEFAULT_IF}" ]; then
    CURRENT_IP=$(ipconfig getifaddr "${DEFAULT_IF}" 2>/dev/null || true)
fi
if [ -z "${CURRENT_IP}" ]; then
    CURRENT_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
fi

# Detect Mac Bonjour local hostname (resolves across same Wi-Fi regardless of IP)
LOCAL_HOST=$(scutil --get LocalHostName 2>/dev/null || hostname -s || echo "macbook")
# No home-LAN addresses (they only add timeouts away from home). LOCAL_IP_URL is set below to the
# server's Tailscale address, tried only if the public Funnel address doesn't answer.
BONJOUR_URL=""
LOCAL_IP_URL=""

# The backend runs on the home Ubuntu server or locally on this Mac
ENV_SERVER_HOST="${OURCHAT_SERVER_HOST:-}"
. "${SCRIPT_DIR}/scripts/server.conf"
SERVER_HOST="${ENV_SERVER_HOST:-${OURCHAT_SERVER_HOST}}"
SERVER_URL="http://${SERVER_HOST}:3001/api/v1"
TAILSCALE_URL="${SERVER_URL}"

# Check if the configured server is responding; if not, check or start local Mac server
if ! curl -fs -m 2 "${SERVER_URL}/health" 2>/dev/null | grep -q '"status":"ok"'; then
    # Keep the Tailscale address anyway: baking this Mac's Wi-Fi IP into the app would break it off-network
    echo "  ! Server (${SERVER_URL}) is not answering from this Mac (is Tailscale on here and on the server?)."
    echo "    The app is still built for ${SERVER_URL}."
fi

# Fetch active Cloudflare quick tunnel address from the running server
TUNNEL_URL="$(curl -fs -m 5 "${SERVER_URL}/network/config" 2>/dev/null \
    | python3 -c 'import sys,json; print((json.load(sys.stdin).get("public_url") or "").replace("/api/v1",""))' 2>/dev/null || true)"
if [ -z "${TUNNEL_URL}" ]; then
    TUNNEL_URL="$(curl -s -m 2 http://127.0.0.1:2000/quicktunnel 2>/dev/null | python3 -c 'import sys,json; h=json.load(sys.stdin).get("hostname"); print(f"https://{h}" if h else "")' 2>/dev/null || true)"
fi
if [ -z "${TUNNEL_URL}" ]; then
    TUNNEL_URL="$(grep -o 'cloudflareURL = "[^"]*' ios/MiniTelegram/Core/Networking/APIClient.swift | sed 's/.*"//; s#/api/v1$##' || true)"
fi

# Primary address: the public Funnel name (any network, no Tailscale needed on the phone);
# the Tailscale address is the fallback
if [ -n "${OURCHAT_PUBLIC_URL:-}" ]; then
    LOCAL_IP_URL="${TAILSCALE_URL}"
    SERVER_URL="${OURCHAT_PUBLIC_URL}/api/v1"
    curl -fs -m 8 "${SERVER_URL}/health" 2>/dev/null | grep -q '"status":"ok"' \
        || echo "  ! ${SERVER_URL} is not answering yet (is Funnel on? sudo tailscale funnel --bg 3001)"
fi

BUILD_ID="$(date +%Y%m%d%H%M%S)"

echo "  ✓ Active Wi-Fi IP:   ${CURRENT_IP}"
echo "  ✓ Active Server:     ${SERVER_URL}"
echo "  ✓ Cloudflare HTTPS:  ${TUNNEL_URL}"

# Dynamically inject fresh network settings into APIClient.swift
python3 -c "
import sys, re
api_file = 'ios/MiniTelegram/Core/Networking/APIClient.swift'
with open(api_file, 'r') as f:
    content = f.read()

new_block = '''// BEGIN_GENERATED_NETWORK_CONFIG
public struct GeneratedNetworkConfig {
    public static let buildId = \"${BUILD_ID}\"
    public static let localBonjourURL = \"${BONJOUR_URL}\"
    public static let localIPURL = \"${LOCAL_IP_URL}\"
    public static let cloudflareURL = \"${TUNNEL_URL}/api/v1\"

    // Public Tailscale Funnel address first (any network), the Tailscale IP as fallback
    public static let defaultURL = \"${SERVER_URL}\"
}
// END_GENERATED_NETWORK_CONFIG'''

pattern = r'// BEGIN_GENERATED_NETWORK_CONFIG.*?// END_GENERATED_NETWORK_CONFIG'
updated = re.sub(pattern, new_block, content, flags=re.DOTALL)
with open(api_file, 'w') as f:
    f.write(updated)
"

# ------------------------------------------------------------------------------
# Serve Only Mode
# ------------------------------------------------------------------------------
if [ "${SERVE_ONLY}" = true ]; then
    echo "🌐 Public Download & Installation Page:"
    echo "   ${TUNNEL_URL}/api/v1/download"
    echo ""
    echo "📦 Direct IPA Download:"
    echo "   ${TUNNEL_URL}/api/v1/download/OurChat.ipa"
    echo "========================================================================"
    exit 0
fi

# ------------------------------------------------------------------------------
# iPhone detection
# ------------------------------------------------------------------------------
# One line per real iPhone/iPad this Mac knows:  udid|name|model|connection|pairing|devmode|ios
#   connection: usb (plugged in now) | wifi (reachable over the network) | offline
# Uses Xcode's JSON device list, not the text table: the table leaves columns blank for phones
# Xcode hasn't fully read yet, and the old "grep physical" therefore hid new phones.
list_iphones() {
    local json
    json="$(mktemp -t ourchat_devices)"
    xcrun devicectl list devices --json-output "${json}" >/dev/null 2>&1 || true
    python3 - "${json}" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw = d.get("hardwareProperties") or {}
    cn = d.get("connectionProperties") or {}
    dp = d.get("deviceProperties") or {}
    if hw.get("reality") == "simulated" or hw.get("platform") not in ("iOS", "iPadOS"):
        continue
    transport = cn.get("transportType")
    connection = "usb" if transport == "wired" else ("wifi" if transport == "localNetwork" else "offline")
    print("|".join([
        hw.get("udid") or d.get("identifier") or "",
        (dp.get("name") or "iPhone").replace("|", "/"),
        hw.get("marketingName") or hw.get("productType") or "iPhone",
        connection,
        cn.get("pairingState") or "unknown",
        dp.get("developerModeStatus") or "unknown",
        dp.get("osVersionNumber") or "?",
    ]))
PY
    rm -f "${json}"
}

# Human-readable list (reads list_iphones lines on stdin)
print_iphones() {
    local udid name model connection pairing devmode ios state
    while IFS='|' read -r udid name model connection pairing devmode ios; do
        [ -z "${udid}" ] && continue
        case "${connection}" in
            usb) state="plugged in (USB)" ;;
            wifi) state="on the network" ;;
            *) state="not connected" ;;
        esac
        echo "    - ${name} — ${model}, iOS ${ios}: ${state}   [${udid}]"
    done
}

if [ "${LIST_ONLY}" = true ]; then
    echo "iPhones this Mac knows:"
    list_iphones | print_iphones
    echo "========================================================================"
    exit 0
fi

# ------------------------------------------------------------------------------
# Step 2: Ensure Infrastructure & Backend Services Are Active
# ------------------------------------------------------------------------------
echo "[2/5] Verifying backend services..."
if curl -fs -m 5 "${SERVER_URL}/health" 2>/dev/null | grep -q '"status":"ok"'; then
    echo "  ✓ Backend API is verified and healthy: ${SERVER_URL}"
else
    echo "  ! ${SERVER_URL} is not reachable from this Mac right now (check Tailscale) — installing anyway."
fi

# ------------------------------------------------------------------------------
# Build and Package Standalone IPA Helper
# ------------------------------------------------------------------------------
package_ipa() {
    echo "🔨 Building generic iOS ARM64 binary..."
    xcodebuild build \
        -project ios/MiniTelegram.xcodeproj \
        -scheme MiniTelegram \
        -destination "generic/platform=iOS" \
        -configuration Debug \
        DEVELOPMENT_TEAM="${TEAM_ID}" \
        CODE_SIGN_STYLE=Automatic \
        "CODE_SIGN_IDENTITY=Apple Development" \
        -allowProvisioningUpdates >/dev/null

    TARGET_BUILD_DIR=$(xcodebuild -project ios/MiniTelegram.xcodeproj -scheme MiniTelegram -destination "generic/platform=iOS" -showBuildSettings | grep -m 1 "TARGET_BUILD_DIR =" | awk '{print $3}')
    APP_PATH="${TARGET_BUILD_DIR}/MiniTelegram.app"

    echo "📦 Packaging dist/OurChat.ipa..."
    mkdir -p dist
    PAYLOAD_TMP="/tmp/OurChat_Package_$$"
    rm -rf "${PAYLOAD_TMP}"
    mkdir -p "${PAYLOAD_TMP}/Payload"
    cp -R "${APP_PATH}" "${PAYLOAD_TMP}/Payload/"
    (cd "${PAYLOAD_TMP}" && zip -qr "${SCRIPT_DIR}/dist/OurChat.ipa" Payload)
    rm -rf "${PAYLOAD_TMP}"

    echo "  ✓ Distributable IPA created: dist/OurChat.ipa ($(ls -lh dist/OurChat.ipa | awk '{print $5}'))"
    echo "  ✓ Public download link: ${TUNNEL_URL}/api/v1/download"
}

if [ "${PACKAGE_ONLY}" = true ]; then
    package_ipa
    echo "========================================================================"
    echo " 🎉 PACKAGE READY FOR REMOTE DEVICES!"
    echo "========================================================================"
    echo "For anyone on another IP or with a different Apple ID:"
    echo "1. Share this link: ${TUNNEL_URL}/api/v1/download"
    echo "2. They download OurChat.ipa"
    echo "3. In Sideloadly or AltStore, enter their own Apple ID and install"
    echo "========================================================================"
    exit 0
fi

# ------------------------------------------------------------------------------
# Step 3: Find the iPhone plugged in by USB
# ------------------------------------------------------------------------------
echo "[3/5] Looking for the iPhone plugged in by USB..."

if [ -z "${DEVICE_UDID}" ]; then
    CANDIDATES=()
    # Plugging in / unlocking takes a moment: wait up to 60 s for a phone on USB
    for attempt in $(seq 1 30); do
        CANDIDATES=()
        while IFS= read -r line; do
            [ -n "${line}" ] && CANDIDATES+=("${line}")
        done < <(list_iphones | awk -F'|' '$4 == "usb"')
        [ "${#CANDIDATES[@]}" -gt 0 ] && break
        [ "${attempt}" -eq 1 ] && echo "  -> No iPhone on USB yet. Plug it in with a data cable and unlock it (waiting up to 60 s)..."
        sleep 2
    done

    # None on USB: phones reachable over the network (Xcode Wi-Fi pairing) also work
    if [ "${#CANDIDATES[@]}" -eq 0 ]; then
        while IFS= read -r line; do
            [ -n "${line}" ] && CANDIDATES+=("${line}")
        done < <(list_iphones | awk -F'|' '$4 == "wifi"')
    fi

    if [ "${#CANDIDATES[@]}" -eq 0 ]; then
        echo "  ✗ No iPhone found on USB."
        echo "    - Use a data cable (some cables only charge) plugged straight into the Mac."
        echo "    - Unlock the iPhone and keep the screen on."
        echo "    - If the iPhone asks 'Trust This Computer?', tap Trust and enter its passcode."
        echo "  iPhones this Mac knows:"
        list_iphones | print_iphones
        echo "  To install another way, build an .ipa: ./scripts/install_device.sh --package-ipa"
        exit 1
    elif [ "${#CANDIDATES[@]}" -eq 1 ]; then
        DEVICE_UDID="${CANDIDATES[0]%%|*}"
    else
        echo "  More than one iPhone is connected. Which one?"
        for i in "${!CANDIDATES[@]}"; do
            IFS='|' read -r c_udid c_name c_model c_conn c_pair c_dev c_ios <<< "${CANDIDATES[$i]}"
            echo "    [$((i+1))] ${c_name} — ${c_model}, iOS ${c_ios} (${c_conn})"
        done
        SELECTION=""
        until [[ "${SELECTION}" =~ ^[0-9]+$ ]] && [ "${SELECTION}" -ge 1 ] && [ "${SELECTION}" -le "${#CANDIDATES[@]}" ]; do
            if ! read -r -p "  Choose 1-${#CANDIDATES[@]}: " SELECTION < /dev/tty; then
                echo "  ✗ No choice made. Run again with: ./scripts/install_device.sh -d <UDID>"
                exit 1
            fi
        done
        DEVICE_UDID="${CANDIDATES[$((SELECTION-1))]%%|*}"
    fi
fi

DEVICE_INFO="$(list_iphones | awk -F'|' -v id="${DEVICE_UDID}" '$1 == id')"
if [ -z "${DEVICE_INFO}" ]; then
    echo "  ✗ This Mac can't see an iPhone with UDID ${DEVICE_UDID}. Plug it in by USB, unlock it, and try again."
    exit 1
fi
IFS='|' read -r _ DEVICE_NAME DEVICE_MODEL DEVICE_CONNECTION DEVICE_PAIRING DEVICE_DEVMODE DEVICE_IOS <<< "${DEVICE_INFO}"
echo "  ✓ Target: ${DEVICE_NAME} — ${DEVICE_MODEL}, iOS ${DEVICE_IOS} (${DEVICE_UDID})"

if [ "${DEVICE_CONNECTION}" = "offline" ]; then
    echo "  ✗ ${DEVICE_NAME} is not connected. Plug it in by USB, unlock it, and try again."
    exit 1
fi

# A phone that has never been used with this Mac has to trust it first
if [ "${DEVICE_PAIRING}" != "paired" ]; then
    echo "  -> On the iPhone, tap 'Trust' and enter its passcode..."
    if ! xcrun devicectl manage pair --device "${DEVICE_UDID}" --timeout 120 >/dev/null 2>&1; then
        echo "  ✗ The iPhone didn't trust this Mac. Unlock it, tap 'Trust This Computer', and run this again."
        exit 1
    fi
    echo "  ✓ The iPhone now trusts this Mac."
fi

# Live status straight from the phone: "<developer mode>|<ready>". The device list above can still
# show an old Developer Mode status (e.g. just switched on and restarted), so never trust it alone.
# ready = the development connection is up and iOS has prepared its developer tools.
device_live_status() {
    local json
    json="$(mktemp -t ourchat_device)"
    xcrun devicectl device info details --device "${DEVICE_UDID}" --json-output "${json}" >/dev/null 2>&1 || true
    python3 - "${json}" <<'PY'
import json, sys
try:
    r = json.load(open(sys.argv[1]))["result"]
except Exception:
    print("unknown|no")
    sys.exit()
cp = r.get("connectionProperties") or {}
dp = r.get("deviceProperties") or {}
ready = cp.get("tunnelState") == "connected" and dp.get("ddiServicesAvailable") is True
print(f'{dp.get("developerModeStatus") or "unknown"}|{"yes" if ready else "no"}')
PY
    rm -f "${json}"
}

LIVE_STATUS="$(device_live_status)"
DEVICE_DEVMODE="${LIVE_STATUS%%|*}"

# Apps from a developer account only run with Developer Mode on
if [ "${DEVICE_DEVMODE}" = "disabled" ]; then
    echo "  ✗ Developer Mode is off on ${DEVICE_NAME}. To turn it on:"
    echo "    1. On the iPhone: Settings > Privacy & Security > Developer Mode > On"
    echo "       (if it isn't listed, leave the phone plugged in, run this script once more, then look again)"
    echo "    2. Restart the iPhone, unlock it and tap 'Turn On'"
    echo "    3. Run this script again"
    exit 1
fi

# The first time a phone is used for development, iOS prepares its developer tools, which can take
# a few minutes. Building before that makes Xcode time out with "preparation errors", so wait for it.
if [ "${LIVE_STATUS##*|}" != "yes" ]; then
    echo "  -> Getting ${DEVICE_NAME} ready for installing (first time can take a few minutes; keep it unlocked)..."
    for attempt in $(seq 1 60); do
        sleep 5
        LIVE_STATUS="$(device_live_status)"
        [ "${LIVE_STATUS##*|}" = "yes" ] && break
        [ $((attempt % 6)) -eq 0 ] && echo "     still preparing... ($((attempt * 5)) s)"
    done
    if [ "${LIVE_STATUS##*|}" != "yes" ]; then
        echo "  ✗ ${DEVICE_NAME} isn't ready yet. Keep it plugged in and unlocked, wait a minute, and run this again."
        echo "    (If it keeps failing: unplug it, restart the iPhone, plug it back in.)"
        exit 1
    fi
fi
echo "  ✓ ${DEVICE_NAME} is ready (Developer Mode on)."

# ------------------------------------------------------------------------------
# Step 4: Compile, sign, and register this iPhone with the developer account
# ------------------------------------------------------------------------------
echo "[4/5] Building Our Chat for ${DEVICE_NAME} (a new iPhone is registered automatically)..."
BUILD_LOG="$(mktemp -t ourchat_build)"
if ! xcodebuild build \
    -project ios/MiniTelegram.xcodeproj \
    -scheme MiniTelegram \
    -destination "platform=iOS,id=${DEVICE_UDID}" \
    -configuration Debug \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_STYLE=Automatic \
    "CODE_SIGN_IDENTITY=Apple Development" \
    -allowProvisioningDeviceRegistration \
    -allowProvisioningUpdates > "${BUILD_LOG}" 2>&1; then
    echo "  ✗ Build or signing failed:"
    grep -E "error:" "${BUILD_LOG}" | sed -E 's/^.*error: /    • /' | sort -u | head -8
    if grep -qiE "preparation errors|Timed out waiting for all destinations" "${BUILD_LOG}"; then
        echo "    → The iPhone wasn't ready yet. Keep it plugged in and unlocked, wait a minute, and run this again."
    elif grep -qiE "needs to be unlocked|device is locked" "${BUILD_LOG}"; then
        echo "    → Unlock the iPhone, keep the screen on, and run this again."
    fi
    if grep -qiE "maximum number|device limit|registered devices" "${BUILD_LOG}"; then
        echo "    → Apple refused to add this iPhone to the developer account (it has a device limit)."
    fi
    if grep -qiE "Developer Mode (is )?disabled|enable Developer Mode" "${BUILD_LOG}"; then
        echo "    → Turn on Developer Mode: Settings > Privacy & Security > Developer Mode."
    fi
    echo "    Full log: ${BUILD_LOG}"
    exit 1
fi
rm -f "${BUILD_LOG}"

TARGET_BUILD_DIR=$(xcodebuild -project ios/MiniTelegram.xcodeproj -scheme MiniTelegram -destination "platform=iOS,id=${DEVICE_UDID}" -showBuildSettings 2>/dev/null | grep -m 1 "TARGET_BUILD_DIR =" | awk '{print $3}')
APP_PATH="${TARGET_BUILD_DIR}/MiniTelegram.app"

# Refresh distributable IPA in dist/
mkdir -p dist
PAYLOAD_TMP="/tmp/OurChat_Payload_$$"
rm -rf "${PAYLOAD_TMP}"
mkdir -p "${PAYLOAD_TMP}/Payload"
cp -R "${APP_PATH}" "${PAYLOAD_TMP}/Payload/"
(cd "${PAYLOAD_TMP}" && zip -qr "${SCRIPT_DIR}/dist/OurChat.ipa" Payload)
rm -rf "${PAYLOAD_TMP}"

echo "  ✓ Build & signing succeeded."

# ------------------------------------------------------------------------------
# Step 5: Install App on Device
# ------------------------------------------------------------------------------
echo "[5/5] Installing Our Chat on ${DEVICE_NAME}..."
INSTALL_LOG="$(mktemp -t ourchat_install)"
if ! xcrun devicectl device install app --device "${DEVICE_UDID}" "${APP_PATH}" > "${INSTALL_LOG}" 2>&1; then
    echo "  ✗ Install failed:"
    grep -iE "error|failed|reason" "${INSTALL_LOG}" | head -6 | sed 's/^/    /'
    echo "    → Keep the iPhone unlocked and plugged in, then run this again. Full log: ${INSTALL_LOG}"
    exit 1
fi
rm -f "${INSTALL_LOG}"
echo "  ✓ App installed on ${DEVICE_NAME}."

echo "  -> Opening the app on the phone..."
if ! xcrun devicectl device process launch --timeout 10 --terminate-existing --device "${DEVICE_UDID}" "${APP_BUNDLE_ID}" >/dev/null 2>&1; then
    echo "  (Installed. If it won't open, see step 1 below, then tap the 'Our Chat' icon.)"
fi

echo "========================================================================"
echo " 🎉 OUR CHAT INSTALLED ON ${DEVICE_NAME}!"
echo "========================================================================"
echo "On this iPhone:"
echo "1. First time only — if it says 'Untrusted Developer':"
echo "   Settings > General > VPN & Device Management > tap the developer profile > Trust"
echo "2. Server: ${SERVER_URL}"
echo "   Internet: ${TUNNEL_URL}/api/v1"
echo "========================================================================"
