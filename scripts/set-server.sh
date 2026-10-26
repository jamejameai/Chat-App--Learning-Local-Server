#!/usr/bin/env bash
# ==============================================================================
# Our Chat — point everything at the home server's new address (after a Wi-Fi change)
#
#   bash scripts/set-server.sh <server-ip>              # check, save, redeploy
#   bash scripts/set-server.sh <server-ip> --no-deploy  # check and save only
#
# On the server, `hostname -I` prints its addresses: use the FIRST one. 172.17.0.1 /
# 172.18.0.1 are Docker's internal networks inside the server and can't be reached.
# ==============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${DIR}/server.conf"
. "${CONF}"

NEW_HOST="${1:-}"
DEPLOY=true
[ "${2:-}" = "--no-deploy" ] && DEPLOY=false

if [ -z "${NEW_HOST}" ]; then
    echo "Usage: bash scripts/set-server.sh <server-ip> [--no-deploy]"
    echo "Current server: ${OURCHAT_SERVER_USER}@${OURCHAT_SERVER_HOST}"
    exit 1
fi
if ! [[ "${NEW_HOST}" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "✗ '${NEW_HOST}' is not an IP address or hostname."
    exit 1
fi

echo "[1/4] Checking ${NEW_HOST} is reachable..."
if ! nc -z -G 5 "${NEW_HOST}" 22 >/dev/null 2>&1; then
    echo "  ✗ Can't reach ${NEW_HOST} (SSH port 22)."
    echo "    - Is this Mac on the same Wi-Fi as the server?"
    echo "    - Use the FIRST address from 'hostname -I' on the server, not 172.17.x / 172.18.x (Docker)."
    exit 1
fi
echo "  ✓ Reachable."

echo "[2/4] Checking it is really the Our Chat server (SSH host key)..."
SCANNED_KEY="$(ssh-keyscan -t ed25519 -T 5 "${NEW_HOST}" 2>/dev/null || true)"
FINGERPRINT="$(printf '%s\n' "${SCANNED_KEY}" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')"
if [ "${FINGERPRINT}" != "${OURCHAT_SERVER_HOSTKEY}" ]; then
    echo "  ✗ ${NEW_HOST} is a different machine (key ${FINGERPRINT:-unknown}, expected ${OURCHAT_SERVER_HOSTKEY})."
    echo "    Nothing was changed."
    exit 1
fi
if ! ssh-keygen -F "${NEW_HOST}" >/dev/null 2>&1; then
    printf '%s\n' "${SCANNED_KEY}" >> "${HOME}/.ssh/known_hosts"
    echo "  ✓ Same server. Trusted its key for ${NEW_HOST}."
else
    echo "  ✓ Same server."
fi

echo "[3/4] Saving ${NEW_HOST} to scripts/server.conf..."
sed -i.bak "s/^OURCHAT_SERVER_HOST=.*/OURCHAT_SERVER_HOST=${NEW_HOST}/" "${CONF}"
rm -f "${CONF}.bak"
echo "  ✓ Saved (was ${OURCHAT_SERVER_HOST})."

if curl -fs -m 5 "http://${NEW_HOST}:3001/api/v1/health" | grep -q '"status":"ok"'; then
    echo "  ✓ Chat server is answering at http://${NEW_HOST}:3001/api/v1"
else
    echo "  ! Chat server not answering yet at http://${NEW_HOST}:3001 (the redeploy below starts it)."
fi

if [ "${DEPLOY}" = true ]; then
    echo "[4/4] Redeploying so voice/video calls use the new address..."
    if ssh -o BatchMode=yes -o ConnectTimeout=8 "${OURCHAT_SERVER_USER}@${NEW_HOST}" true 2>/dev/null; then
        bash "${DIR}/deploy-lan.sh"
    else
        echo "  ! SSH login needs your key. Run these two commands, then you're done:"
        echo "      ssh-add --apple-use-keychain ~/.ssh/id_ed25519"
        echo "      bash scripts/deploy-lan.sh"
    fi
else
    echo "[4/4] Skipped redeploy (--no-deploy)."
fi

echo ""
echo "Phones keep working: away from the old address they switch to the internet address by themselves."
echo "To make phones use the new home address directly (faster on home Wi-Fi), reinstall:"
echo "    ./scripts/install_device.sh -d <iPhone UDID>"
