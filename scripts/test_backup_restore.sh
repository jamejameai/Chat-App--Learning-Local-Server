#!/usr/bin/env bash
# ==============================================================================
# Mini Telegram — Automated Backup & Restore Drill Test Suite
# ==============================================================================
# Validates:
# - Cryptographic archive packaging
# - SHA-256 integrity generation & tamper rejection
# - Client-side AES-256-CBC PBKDF2 encryption/decryption round-trip
# - Data reconstruction and byte-for-byte fidelity
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR=$(mktemp -d -t minitelegram_test_dr_XXXXXX)
trap 'rm -rf "${TEST_DIR}"' EXIT

echo "========================================================================"
echo " Running Automated Backup & Disaster Recovery Verification Tests"
echo " Test Sandbox: ${TEST_DIR}"
echo "========================================================================"

# Test 1: Generate Mock Database & Uploads Data
echo "[Test 1/5] Generating mock database and attachment state..."
mkdir -p "${TEST_DIR}/source/uploads"
echo "CREATE TABLE users (id UUID PRIMARY KEY, username VARCHAR(32));" > "${TEST_DIR}/source/database.sql"
echo "INSERT INTO users VALUES ('c1111111-1111-1111-1111-111111111111', 'alice');" >> "${TEST_DIR}/source/database.sql"
gzip -9 < "${TEST_DIR}/source/database.sql" > "${TEST_DIR}/source/database.sql.gz"

echo "encrypted_binary_payload_attachment_1_test" > "${TEST_DIR}/source/uploads/file1.bin"
echo "encrypted_binary_payload_attachment_2_test" > "${TEST_DIR}/source/uploads/file2.bin"
tar -czf "${TEST_DIR}/source/uploads.tar.gz" -C "${TEST_DIR}/source/uploads" .

# Test 2: Cryptographic Checksum Generation
echo "[Test 2/5] Testing SHA-256 Checksum Generation & Validation..."
cd "${TEST_DIR}/source"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum database.sql.gz uploads.tar.gz > SHA256SUMS.txt
    sha256sum -c SHA256SUMS.txt
else
    shasum -a 256 database.sql.gz uploads.tar.gz > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
fi
echo "  -> Checksum verification passed."

# Test 3: Tamper Detection (Bit-rot rejection)
echo "[Test 3/5] Testing Tamper Detection on corrupt archive..."
cp "${TEST_DIR}/source/database.sql.gz" "${TEST_DIR}/source/database_tampered.sql.gz"
echo "tamper" >> "${TEST_DIR}/source/database_tampered.sql.gz"

# Verify tamper check fails
set +e
if command -v sha256sum >/dev/null 2>&1; then
    sed -i.bak 's/database.sql.gz/database_tampered.sql.gz/' SHA256SUMS.txt
    sha256sum -c SHA256SUMS.txt >/dev/null 2>&1
    RESULT=$?
else
    sed -i.bak 's/database.sql.gz/database_tampered.sql.gz/' SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt >/dev/null 2>&1
    RESULT=$?
fi
set -e

if [ $RESULT -ne 0 ]; then
    echo "  -> Tamper detected and rejected as required! (Exit code: ${RESULT})"
else
    echo "  [x] Error: Tampered file was NOT rejected!"
    exit 1
fi

# Restore clean checksum file
mv "${TEST_DIR}/source/SHA256SUMS.txt.bak" "${TEST_DIR}/source/SHA256SUMS.txt"
rm -f "${TEST_DIR}/source/database_tampered.sql.gz"

# Test 4: AES-256-CBC PBKDF2 Encryption & Decryption Round-trip
echo "[Test 4/5] Testing AES-256-CBC PBKDF2 Encryption Round-trip..."
TEST_PASSPHRASE="super_secure_recovery_passphrase_2026"
PACKAGE_TAR="${TEST_DIR}/archive.tar.gz"
ENCRYPTED_PKG="${TEST_DIR}/archive.tar.gz.enc"
DECRYPTED_TAR="${TEST_DIR}/archive_decrypted.tar.gz"

mkdir -p "${TEST_DIR}/pkg_staging/20261017_120000"
cp "${TEST_DIR}/source/database.sql.gz" "${TEST_DIR}/pkg_staging/20261017_120000/"
cp "${TEST_DIR}/source/uploads.tar.gz" "${TEST_DIR}/pkg_staging/20261017_120000/"
cp "${TEST_DIR}/source/SHA256SUMS.txt" "${TEST_DIR}/pkg_staging/20261017_120000/"

tar -czf "${PACKAGE_TAR}" -C "${TEST_DIR}/pkg_staging" "20261017_120000"

# Encrypt
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
    -in "${PACKAGE_TAR}" \
    -out "${ENCRYPTED_PKG}" \
    -k "${TEST_PASSPHRASE}"

# Decrypt
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
    -in "${ENCRYPTED_PKG}" \
    -out "${DECRYPTED_TAR}" \
    -k "${TEST_PASSPHRASE}"

# Verify tar checksums match
ORIG_HASH=$(openssl dgst -sha256 "${PACKAGE_TAR}" | awk '{print $NF}')
DECR_HASH=$(openssl dgst -sha256 "${DECRYPTED_TAR}" | awk '{print $NF}')

if [ "${ORIG_HASH}" = "${DECR_HASH}" ]; then
    echo "  -> AES-256-CBC decryption matches original byte-for-byte! SHA256: ${ORIG_HASH}"
else
    echo "  [x] Error: Decrypted hash does not match original!"
    exit 1
fi

# Test 5: Full Extraction & Data Fidelity
echo "[Test 5/5] Testing Data Extraction Fidelity..."
mkdir -p "${TEST_DIR}/restored"
tar -xzf "${DECRYPTED_TAR}" -C "${TEST_DIR}/restored"
RESTORED_DIR="${TEST_DIR}/restored/20261017_120000"

gunzip -c "${RESTORED_DIR}/database.sql.gz" > "${TEST_DIR}/restored/database.sql"
if grep -q "alice" "${TEST_DIR}/restored/database.sql"; then
    echo "  -> SQL database dump verified intact with test records."
else
    echo "  [x] Error: Restored SQL missing records!"
    exit 1
fi

mkdir -p "${TEST_DIR}/restored/uploads"
tar -xzf "${RESTORED_DIR}/uploads.tar.gz" -C "${TEST_DIR}/restored/uploads"
if [ -f "${TEST_DIR}/restored/uploads/file1.bin" ] && [ -f "${TEST_DIR}/restored/uploads/file2.bin" ]; then
    echo "  -> Attachment files verified intact."
else
    echo "  [x] Error: Restored uploads missing files!"
    exit 1
fi

echo "========================================================================"
echo " All 5 Automated Backup & Disaster Recovery Tests PASSED!"
echo "========================================================================"
