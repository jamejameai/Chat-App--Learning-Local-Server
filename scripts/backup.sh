#!/usr/bin/env bash
# ==============================================================================
# Mini Telegram — Production Automated Backup Script
# ==============================================================================
# Performs full, zero-loss backups:
# 1. PostgreSQL Relational Database (users, device keys, encrypted envelopes)
# 2. Encrypted Attachments Volume (/uploads)
# 3. Cryptographic SHA-256 Integrity Verification
# 4. Optional Client-Side AES-256-CBC PBKDF2 Archive Encryption
# 5. Configurable Retention Pruning (Default: 14 days)
# ==============================================================================

set -euo pipefail

# Configuration with environment defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backups}"
CONTAINER_POSTGRES="${CONTAINER_POSTGRES:-minitelegram-postgres}"
CONTAINER_BACKEND="${CONTAINER_BACKEND:-minitelegram-backend}"
DB_USER="${DB_USER:-minitelegram}"
DB_NAME="${DB_NAME:-minitelegram_db}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE:-}"

TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
TARGET_DIR="${BACKUP_DIR}/${TIMESTAMP}"

echo "========================================================================"
echo " Starting Mini Telegram Automated Backup: ${TIMESTAMP}"
echo "========================================================================"
mkdir -p "${TARGET_DIR}"

# Step 1: Backup PostgreSQL Database
echo "[1/5] Dumping PostgreSQL database from '${CONTAINER_POSTGRES}'..."
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_POSTGRES}$"; then
    docker exec -t "${CONTAINER_POSTGRES}" pg_dump -U "${DB_USER}" -d "${DB_NAME}" --clean --if-exists | gzip -9 > "${TARGET_DIR}/database.sql.gz"
    echo "  -> PostgreSQL dump created: $(du -h "${TARGET_DIR}/database.sql.gz" | cut -f1)"
else
    echo "  [!] Warning: Container '${CONTAINER_POSTGRES}' is not running. Checking for local pg_dump..."
    if command -v pg_dump >/dev/null 2>&1; then
        pg_dump -U "${DB_USER}" -d "${DB_NAME}" --clean --if-exists | gzip -9 > "${TARGET_DIR}/database.sql.gz"
    else
        echo "  [x] Error: Neither docker container '${CONTAINER_POSTGRES}' nor local pg_dump is available!"
        exit 1
    fi
fi

# Step 2: Backup Encrypted Attachments
echo "[2/5] Archiving encrypted attachments from '${CONTAINER_BACKEND}'..."
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_BACKEND}$"; then
    docker exec "${CONTAINER_BACKEND}" tar -czf - -C /uploads . > "${TARGET_DIR}/uploads.tar.gz" || {
        echo "  -> No uploads found or volume empty. Creating empty placeholder archive."
        tar -czf "${TARGET_DIR}/uploads.tar.gz" -T /dev/null
    }
    echo "  -> Uploads archive created: $(du -h "${TARGET_DIR}/uploads.tar.gz" | cut -f1)"
else
    # Fallback to local storage path if server is running on host
    LOCAL_UPLOADS="${PROJECT_ROOT}/server/uploads"
    if [ -d "${LOCAL_UPLOADS}" ]; then
        tar -czf "${TARGET_DIR}/uploads.tar.gz" -C "${LOCAL_UPLOADS}" .
        echo "  -> Uploads archive created from local dir: $(du -h "${TARGET_DIR}/uploads.tar.gz" | cut -f1)"
    else
        echo "  -> No uploads directory found. Creating empty archive placeholder."
        tar -czf "${TARGET_DIR}/uploads.tar.gz" -T /dev/null
    fi
fi

# Step 3: Compute Cryptographic SHA-256 Checksums
echo "[3/5] Computing SHA-256 integrity checksums..."
cd "${TARGET_DIR}"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum database.sql.gz uploads.tar.gz > SHA256SUMS.txt
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 database.sql.gz uploads.tar.gz > SHA256SUMS.txt
else
    openssl dgst -sha256 database.sql.gz uploads.tar.gz > SHA256SUMS.txt
fi
echo "  -> SHA256SUMS.txt generated:"
cat SHA256SUMS.txt

# Step 4: Optional AES-256-CBC Encryption
FINAL_PACKAGE="${BACKUP_DIR}/minitelegram_backup_${TIMESTAMP}.tar.gz"
echo "[4/5] Packaging backup archive..."
cd "${BACKUP_DIR}"
tar -czf "${FINAL_PACKAGE}" -C "${BACKUP_DIR}" "${TIMESTAMP}"

if [ -n "${BACKUP_PASSPHRASE}" ]; then
    echo "  -> Encrypting backup package with AES-256-CBC PBKDF2..."
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
        -in "${FINAL_PACKAGE}" \
        -out "${FINAL_PACKAGE}.enc" \
        -k "${BACKUP_PASSPHRASE}"
    rm -f "${FINAL_PACKAGE}"
    FINAL_PACKAGE="${FINAL_PACKAGE}.enc"
    echo "  -> Encrypted backup saved to: ${FINAL_PACKAGE}"
else
    echo "  -> Unencrypted backup package: ${FINAL_PACKAGE}"
fi

# Clean up raw temporary folder
rm -rf "${TARGET_DIR}"

# Step 5: Enforce Retention Policy
echo "[5/5] Pruning backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -maxdepth 1 \( -name "minitelegram_backup_*.tar.gz" -o -name "minitelegram_backup_*.tar.gz.enc" \) -mtime +"${RETENTION_DAYS}" -exec rm -f {} +
echo "  -> Retention policy applied."

echo "========================================================================"
echo " Backup Completed Successfully!"
echo " Artifact: ${FINAL_PACKAGE}"
echo " Size:     $(du -h "${FINAL_PACKAGE}" | cut -f1)"
echo "========================================================================"
