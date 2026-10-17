# Mini Telegram — Production Operations & Maintenance Manual

This manual provides complete day-to-day operational procedures, performance tuning guidelines, disaster recovery runbooks, and incident response strategies for self-hosting the **Mini Telegram** private communication platform.

---

## 1. Day-1 Deployment Runbook

### 1.1 Prerequisites
- Linux host (Ubuntu 22.04/24.04 LTS or Debian 12 recommended) or macOS Apple Silicon.
- Docker Engine 24.0+ & Docker Compose v2.20+.
- Domain name or DDNS hostname pointing to the server's public WAN IP.
- Ports `80/tcp`, `443/tcp`, `7880/tcp`, `3478/udp`, `5349/udp`, `50000-50050/udp` forwarded on router.

### 1.2 Initial Bootstrap
```bash
# 1. Clone repository
git clone https://github.com/your-org/mini-telegram.git /opt/minitelegram
cd /opt/minitelegram

# 2. Configure production secrets
cp .env.example .env
chmod 600 .env

# Generate high-entropy secrets
sed -i "s/change_this_to_a_secure_database_password/$(openssl rand -hex 32)/" .env
sed -i "s/replace_with_a_64_char_cryptographically_secure_random_string_access/$(openssl rand -hex 32)/" .env
sed -i "s/replace_with_a_64_char_cryptographically_secure_random_string_refresh/$(openssl rand -hex 32)/" .env
sed -i "s/secret_livekit_key_replace_for_production/$(openssl rand -hex 32)/" .env

# 3. Launch stack using production Compose profile
docker compose -f infrastructure/docker-compose.prod.yml up -d --build

# 4. Verify service health
docker compose -f infrastructure/docker-compose.prod.yml ps
```

---

## 2. Resource Management & Performance Tuning

### 2.1 Memory & CPU Limits
Production containers are governed by strict resource ceilings in `docker-compose.prod.yml`:
- **NestJS Backend**: 2 CPUs max, 2048 MB RAM limit (512 MB reserved).
- **PostgreSQL 16**: 2 CPUs max, 1536 MB RAM limit (512 MB reserved).
- **LiveKit SFU**: 2 CPUs max, 1024 MB RAM limit (256 MB reserved).
- **Caddy Reverse Proxy**: 1 CPU max, 512 MB RAM limit (128 MB reserved).
- **Coturn Relay**: 1 CPU max, 512 MB RAM limit (128 MB reserved).

### 2.2 PostgreSQL Performance Tuning
Configured via Docker command parameters:
- `shared_buffers = 256MB`: Memory dedicated to PostgreSQL shared memory cache.
- `effective_cache_size = 768MB`: Estimate of total memory available for disk caching.
- `maintenance_work_mem = 64MB`: Allocated for VACUUM and CREATE INDEX operations.
- `checkpoint_completion_target = 0.9`: Smooths disk I/O spikes during checkpoints.
- `max_connections = 100`: Connection ceiling preventing exhaustion.

---

## 3. Maintenance, Upgrades & Zero-Downtime Migration

### 3.1 Applying Software Updates
```bash
cd /opt/minitelegram
git pull origin main

# Build updated backend image
docker compose -f infrastructure/docker-compose.prod.yml build backend

# Re-create backend container with zero state loss
docker compose -f infrastructure/docker-compose.prod.yml up -d --no-deps backend

# Execute database schema migrations if new migrations exist
docker exec -t minitelegram-backend npx ts-node dist/database/migrate.js
```

### 3.2 Database Migration Integrity
All migrations in `server/src/database/migrations/` execute within atomic transactions (`BEGIN ... COMMIT`). If any migration step encounters an error, the transaction rolls back cleanly with zero data corruption.

---

## 4. Automated Backup, Retention & Disaster Recovery

### 4.1 Scheduled Daily Backups
A cron wrapper is provided at `scripts/cron_backup.sh`. Configure daily execution via crontab:
```bash
# Open crontab editor
crontab -e

# Run daily at 03:00 AM server time
0 3 * * * /opt/minitelegram/scripts/cron_backup.sh >> /var/log/minitelegram-backup.log 2>&1
```

### 4.2 On-Demand Encrypted Backup
```bash
# Execute full encrypted backup using environment passphrase
BACKUP_PASSPHRASE="your_strong_backup_encryption_passphrase" ./scripts/backup.sh
```

The backup produces a compressed, AES-256-CBC encrypted bundle containing:
1. `database.sql.gz`: Full PostgreSQL database dump with all tables, keys, and message metadata.
2. `uploads.tar.gz`: All encrypted zero-knowledge file attachments.
3. `SHA256SUMS.txt`: Cryptographic hashes verifying absence of bit rot.

### 4.3 Disaster Recovery Procedure
In the event of hardware failure or server replacement:
```bash
# 1. On clean host, clone repo and start fresh containers
docker compose -f infrastructure/docker-compose.prod.yml up -d postgres backend

# 2. Execute restore script
./scripts/restore.sh --yes /path/to/minitelegram_backup_20261017_120000.tar.gz.enc "your_passphrase"

# 3. Verify restore integrity
curl -s http://127.0.0.1:3000/api/v1/health | jq
```

### 4.4 Automated DR Drill Test
Verify the backup and restore pipeline at any time without disturbing live data:
```bash
./scripts/test_backup_restore.sh
```

---

## 5. Monitoring, Health Checks & Log Management

### 5.1 Health Check Endpoints
- **HTTP Health Probe**: `GET /api/v1/health`
  - Returns `200 OK` with status `ok`, database latency, uptime, and storage readiness.
- **Docker Native Probes**: Every container is monitored every 10–30s. Unhealthy containers restart automatically.

### 5.2 Log Rotation Policy
To prevent unmanaged container logs from exhausting disk space, all services enforce:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "20m"
    max-file: "5"
```
Maximum log consumption per container is capped at 100 MB.

---

## 6. Security Incident Response Runbook

### 6.1 Compromised Device Revocation
If a team member loses their iPhone or reports a compromised device:
1. An administrator navigates to **Settings -> Device Management** on their iOS client.
2. Locate the compromised device ID and tap **Revoke Device**.
3. The server immediately:
   - Deletes active refresh tokens and invalidates JWT sessions.
   - Marks the device record as `revoked_at = NOW()`.
   - Purges pending prekey bundles from the database.
   - Broadcasts device revocation over WebSocket to terminate any open connections.

### 6.2 Eviction Re-Keying for Group Chats
When removing an untrusted member from a group:
1. Group Admin or Owner removes the user in **Group Info**.
2. The server removes their membership and broadcasts `conversation.rekey_required`.
3. All remaining iOS clients immediately rotate their Sender Key, discard the prior chain key, and re-distribute the new Sender Key encrypted via 1:1 Double Ratchet channels.
4. The evicted member's device can never decrypt future messages or voice notes.

### 6.3 Emergency Server Lockdown
If the backend host is compromised:
```bash
# Instantly terminate all ingress connections
docker compose -f infrastructure/docker-compose.prod.yml stop reverse-proxy backend

# Rotate all database passwords and JWT secrets in .env
# Re-launch with new cryptographic secrets
docker compose -f infrastructure/docker-compose.prod.yml up -d
```
Because all messages, files, and voice notes are end-to-end encrypted with zero-knowledge keys stored exclusively in Apple Secure Enclave / Keychain on physical iOS devices, **zero message plaintext is leaked even if the host database is breached**.

---

## 7. WebRTC & NAT Traversal Troubleshooting

### 7.1 Testing Coturn STUN/TURN Connectivity
```bash
# Inspect Coturn connection log
docker logs -f minitelegram-coturn

# Verify STUN binding locally using turnutils_uclient
docker exec -t minitelegram-coturn turnutils_uclient -s -u minitelegram -w coturn_credential_secret 127.0.0.1
```

### 7.2 Testing LiveKit SFU Routing
```bash
# Check LiveKit room status and WebRTC ingress
curl -s http://127.0.0.1:7880/
docker logs -f minitelegram-livekit
```

### 7.3 Carrier-Grade NAT (CGNAT) Solutions
If your ISP does not allocate a public IPv4 address (WAN IP in `100.64.0.0/10`):
- **Option 1**: Configure a Tailscale subnet router or Headscale mesh network between your home server and team devices.
- **Option 2**: Deploy Coturn and Caddy on an external $3/mo cloud VPS (e.g., Hetzner / Scaleway) and route WebSocket and WebRTC traffic through a WireGuard tunnel to your home server.
