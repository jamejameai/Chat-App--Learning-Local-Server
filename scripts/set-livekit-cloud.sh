#!/usr/bin/env bash
# ==============================================================================
# Our Chat — run calls through LiveKit Cloud (works from anywhere), or back on the home server
#
#   bash scripts/set-livekit-cloud.sh         # asks for the project URL, API key and secret
#   bash scripts/set-livekit-cloud.sh --off   # calls go back to the LiveKit on the home server
#
# The values are typed here (the secret is hidden) and written straight into the server's
# private infrastructure/.env (mode 600). They never go into this repository.
# Only calls use LiveKit Cloud; chat, photos and voice messages stay on the home server.
# ==============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${DIR}/server.conf"
REMOTE="${REMOTE:-${OURCHAT_SERVER_USER}@${OURCHAT_SERVER_HOST}}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "${REMOTE}")
ENV_DIR="our-chat/infrastructure"
COMPOSE="docker compose -f infrastructure/docker-compose.lan.yml --env-file infrastructure/.env"

"${SSH[@]}" true </dev/null 2>/dev/null || {
    echo "✗ Can't log in to ${REMOTE}. Unlock your SSH key first:"
    echo "    ssh-add --apple-use-keychain ~/.ssh/id_ed25519"
    exit 1
}

if [ "${1:-}" = "--off" ]; then
    echo "[1/2] Removing the LiveKit Cloud settings from the server..."
    "${SSH[@]}" "sed -i '/^LIVEKIT_CLOUD_/d' ${ENV_DIR}/.env" </dev/null
    echo "[2/2] Redeploying (calls use the home server again)..."
    bash "${DIR}/deploy-lan.sh"
    exit 0
fi

echo "From cloud.livekit.io → your project → Settings → Keys:"
read -r -p "  Project URL (wss://....livekit.cloud): " URL
read -r -p "  API Key: " KEY
read -r -s -p "  API Secret (hidden): " SECRET
echo

URL="${URL%/}"
if ! [[ "${URL}" =~ ^wss://[A-Za-z0-9.-]+$ ]]; then
    echo "✗ The URL should look like wss://your-project.livekit.cloud"
    exit 1
fi
if ! [[ "${KEY}" =~ ^[A-Za-z0-9]+$ ]] || ! [[ "${SECRET}" =~ ^[A-Za-z0-9]+$ ]]; then
    echo "✗ The API key and secret should be letters and numbers only (copy them again)."
    exit 1
fi

echo "[1/3] Saving to the server's private settings..."
# Values travel over SSH stdin, so they never appear in a command line
printf '%s\n%s\n%s\n' "${URL}" "${KEY}" "${SECRET}" | "${SSH[@]}" "cd ${ENV_DIR} && umask 077 && {
    read -r U; read -r K; read -r S
    sed -i '/^LIVEKIT_CLOUD_/d' .env
    printf 'LIVEKIT_CLOUD_URL=%s\nLIVEKIT_CLOUD_API_KEY=%s\nLIVEKIT_CLOUD_API_SECRET=%s\n' \"\$U\" \"\$K\" \"\$S\" >> .env
    chmod 600 .env
}"
echo "  ✓ Saved."

echo "[2/3] Redeploying..."
bash "${DIR}/deploy-lan.sh" </dev/null >/dev/null
echo "  ✓ Server restarted with LiveKit Cloud."

echo "[3/3] Checking the key and secret with LiveKit Cloud..."
if "${SSH[@]}" "cd our-chat && ${COMPOSE} exec -T backend node -e '
const { RoomServiceClient } = require(\"livekit-server-sdk\");
const url = process.env.LIVEKIT_PUBLIC_URL.replace(/^wss:/, \"https:\");
new RoomServiceClient(url, process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET)
  .listRooms()
  .then(() => { console.log(\"  ✓ LiveKit Cloud accepted the key: calls now work from anywhere.\"); })
  .catch((e) => { console.error(\"  ✗ LiveKit Cloud refused: \" + e.message); process.exit(1); });
'" </dev/null; then
    exit 0
fi
echo "    Check the URL, key and secret in your LiveKit project and run this script again."
exit 1
