# Mini Telegram (iOS & Self-Hosted Monolith)

Mini Telegram is an end-to-end encrypted, private, invite-only team communication system built natively for iPhone (Swift / SwiftUI) and powered by a self-hosted modular monolith backend (NestJS, TypeScript, PostgreSQL, WebSockets, LiveKit SFU).

Designed specifically for private teams and research groups (10–50 users) who demand complete infrastructure sovereignty and uncompromising cryptographic privacy.

---

## Key Capabilities

- **Strict Invite-Only Onboarding**: Public registration is physically barred; registration requires an unexpired, cryptographically generated token issued by the Super-Admin.
- **Auditable End-to-End Encryption**: Built using the canonical Signal Double Ratchet algorithm, X3DH key agreement, and Sender Keys for group messaging, implemented natively via Apple's FIPS 140-2 validated CryptoKit framework.
- **Client-Side Encrypted File Sharing**: High-entropy AES-256-GCM symmetric encryption for attachments; the server only stores and routes opaque ciphertext blobs.
- **Real-Time Voice & Video Calling**: One-to-one and group meetings backed by WebRTC and a self-hosted LiveKit SFU with client-side FrameCryptor E2EE.
- **Full Offline Synchronization**: SQLite persistent outbox with bounded exponential retries and monotonic gap-detection sync cursors.
- **First-Class Bilingual Localization**: Complete native English and Khmer (`km`) language support with immediate runtime language switching without restarting the app.
- **Privacy-First Push Notifications**: Zero plaintext or cryptographic secrets in APNs push payloads.
- **Self-Hosted Infrastructure**: Turnkey Docker Compose orchestration for PostgreSQL 16, LiveKit, coturn STUN/TURN, and Caddy reverse proxy.

---

## Documentation Index

Detailed architectural and technical records:

- 📐 [**Architecture Specification**](file:///Users/macbook/NEW-GEN/docs/ARCHITECTURE.md) — System topology, MVVM design, dependency injection container, and component interaction.
- 🔐 [**Cryptographic & E2EE Specification**](file:///Users/macbook/NEW-GEN/docs/ENCRYPTION.md) — Detailed evaluation of Signal vs MLS, Double Ratchet, X3DH, Sender Keys, and key lifecycle.
- 🛡️ [**Security & Hardening Guide**](file:///Users/macbook/NEW-GEN/docs/SECURITY.md) — Threat model, token rotation, Keychain protection, and rate limiting.
- 📞 [**Calling & Media Architecture**](file:///Users/macbook/NEW-GEN/docs/CALLING.md) — WebRTC, LiveKit SFU, FrameCryptor E2EE, and audio route management.
- 🗄️ [**Database & Integrity Schema**](file:///Users/macbook/NEW-GEN/docs/DATABASE.md) — PostgreSQL schema, monotonic sequence locking, indexes, and constraints.
- 🔌 [**API & WebSocket Gateway**](file:///Users/macbook/NEW-GEN/docs/API.md) — REST endpoints and bidirectional real-time event definitions.
- 🚀 [**Deployment & Home Server Setup**](file:///Users/macbook/NEW-GEN/docs/DEPLOYMENT.md) — Docker Compose, static IP reservation, firewall rules, and CGNAT workarounds.
- 💾 [**Backup & Disaster Recovery**](file:///Users/macbook/NEW-GEN/docs/BACKUP-RECOVERY.md) — Automated database dumps, encrypted uploads archiving, and recovery drills.
- 🛠️ [**Development Workflow**](file:///Users/macbook/NEW-GEN/docs/DEVELOPMENT.md) — Local environment setup and testing commands.

---

## Quick Start

### 1. Configure Environment
```bash
cp .env.example .env
```

### 2. Run Backend Services (Docker)
```bash
docker compose -f infrastructure/docker-compose.yml up -d
```

### 3. Open iOS Client
Open `ios/MiniTelegram.xcodeproj` in Xcode or run via command line build tools.
