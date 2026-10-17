#!/usr/bin/env bash
# ==============================================================================
# Mini Telegram — Cron Wrapper for Automated Daily Backups
# ==============================================================================
# Usage in crontab (e.g. daily at 02:00 AM):
# 0 2 * * * /path/to/mini-telegram/scripts/cron_backup.sh >> /var/log/minitelegram-backup.log 2>&1
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source production environment if exists
if [ -f "${PROJECT_ROOT}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
    set +a
fi

LOG_FILE="${LOG_FILE:-${PROJECT_ROOT}/backups/backup.log}"
mkdir -p "$(dirname "${LOG_FILE}")"

echo "=== [$(date --iso-8601=seconds 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")] Starting Daily Automated Backup ===" >> "${LOG_FILE}"

if "${SCRIPT_DIR}/backup.sh" >> "${LOG_FILE}" 2>&1; then
    echo "=== [$(date --iso-8601=seconds 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")] Daily Backup Finished Successfully ===" >> "${LOG_FILE}"
else
    STATUS=$?
    echo "=== [$(date --iso-8601=seconds 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")] Daily Backup FAILED with code ${STATUS} ===" >> "${LOG_FILE}"
    exit "${STATUS}"
fi
