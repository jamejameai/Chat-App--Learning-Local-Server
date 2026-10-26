#!/usr/bin/env bash
# ==============================================================================
# Our Chat — upload dist/OurChat.ipa to the home Ubuntu server, so anyone can
# download it from <server>/api/v1/download and install it with their own Apple ID
# (Sideloadly / AltStore). Run by install_device.sh --package-ipa and deploy-lan.sh.
#
#   bash scripts/publish-ipa.sh
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/server.conf"
REMOTE="${REMOTE:-${OURCHAT_SERVER_USER}@${OURCHAT_SERVER_HOST}}"
REMOTE_DIR="${REMOTE_DIR:-our-chat}"
IPA="${ROOT}/dist/OurChat.ipa"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "${REMOTE}")

if [ ! -f "${IPA}" ]; then
    echo "  ✗ ${IPA} does not exist. Build it first: ./scripts/install_device.sh --package-ipa"
    exit 1
fi

echo "  -> Uploading OurChat.ipa ($(ls -lh "${IPA}" | awk '{print $5}')) to ${REMOTE}..."
# Upload to a temporary name, then rename: a download in progress never gets a half-written file
if ! "${SSH[@]}" "mkdir -p ${REMOTE_DIR}/downloads && cat > ${REMOTE_DIR}/downloads/.OurChat.ipa.part && mv -f ${REMOTE_DIR}/downloads/.OurChat.ipa.part ${REMOTE_DIR}/downloads/OurChat.ipa" < "${IPA}"; then
    echo "  ✗ Upload failed. Is the server on (${OURCHAT_SERVER_HOST}) and the SSH key loaded (ssh-add -l)?"
    exit 1
fi
echo "  ✓ Uploaded to ~/${REMOTE_DIR}/downloads/OurChat.ipa"
