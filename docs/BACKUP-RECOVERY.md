# Mini Telegram — Backup & Disaster Recovery Guide

## 1. Backup Strategy

To ensure zero data loss on a home server, backups must cover two distinct data tiers:
1. **PostgreSQL Relational Database**: User records, device keys, encrypted envelopes, audit trails.
2. **Encrypted Attachment Storage**: The physical encrypted ciphertext blobs stored in `/uploads`.

---

## 2. Automated Daily Backup Script

Save the following automated backup script at `infrastructure/scripts/backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/var/backups/minitelegram"
DATE=$(date +"%Y%m%d_%H%M%S")
TARGET_DIR="${BACKUP_DIR}/${DATE}"

mkdir -p "${TARGET_DIR}"

echo "[+] Starting Mini Telegram Backup: ${DATE}"

# 1. Backup PostgreSQL Database
docker exec -t minitelegram-postgres pg_dump -U minitelegram minitelegram_db | gzip > "${TARGET_DIR}/database.sql.gz"
echo "[+] PostgreSQL backup completed."

# 2. Backup Encrypted Uploads
tar -czf "${TARGET_DIR}/uploads.tar.gz" -C /var/lib/minitelegram/uploads .
echo "[+] Uploads backup completed."

# 3. Compute SHA-256 Checksums
cd "${TARGET_DIR}"
sha256sum * > SHA256SUMS.txt

# 4. Enforce Retention (Prune backups older than 14 days)
find "${BACKUP_DIR}" -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
echo "[+] Backup finished successfully at: ${TARGET_DIR}"
```

---

## 3. Disaster Recovery & Restoration Procedure

In the event of hardware failure, disk corruption, or replacement of the home server:

### Step 1: Provision Clean Machine
Install Docker and Docker Compose on the new host, clone the repository, and recreate `.env` using your securely preserved master keys.

### Step 2: Restore PostgreSQL Database
```bash
# 1. Ensure the PostgreSQL container is started
docker compose -f infrastructure/docker-compose.yml up -d postgres

# 2. Wait for database readiness
until docker exec minitelegram-postgres pg_isready -U minitelegram; do
    echo "Waiting for postgres..."
    sleep 2
done

# 3. Restore dump
gunzip -c /path/to/backup/database.sql.gz | docker exec -i minitelegram-postgres psql -U minitelegram minitelegram_db
```

### Step 3: Restore Encrypted Uploads
```bash
tar -xzf /path/to/backup/uploads.tar.gz -C /var/lib/minitelegram/uploads
```

### Step 4: Start Full Stack
```bash
docker compose -f infrastructure/docker-compose.yml up -d
docker compose -f infrastructure/docker-compose.yml ps
```
The system will resume with zero message or key loss.
