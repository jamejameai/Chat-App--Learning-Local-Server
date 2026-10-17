# Changelog

All notable changes to the Mini Telegram project are documented in this file.

## [Phase 0] - 2026-10-17
### Added
- Environment and toolchain inspection (macOS arm64, Xcode 27, Swift 6, Node v24, Docker 29).
- Technical decisions and protocol evaluation:
  - Cryptographic evaluation: Signal Double Ratchet + X3DH + Sender Keys utilizing Apple CryptoKit hardware primitives.
  - Calling evaluation: WebRTC + self-hosted LiveKit SFU + FrameCryptor E2EE.
  - Home server network hosting analysis (DDNS, Static DHCP, Port Forwarding, CGNAT fallbacks).
- Architecture and specification deliverables:
  - `docs/ARCHITECTURE.md`
  - `docs/SECURITY.md`
  - `docs/ENCRYPTION.md`
  - `docs/CALLING.md`
  - `docs/DEPLOYMENT.md`
  - `docs/DATABASE.md`
  - `docs/API.md`
  - `docs/BACKUP-RECOVERY.md`
  - `docs/DEVELOPMENT.md`
- Project root scaffolding:
  - `README.md`
  - `.gitignore`
  - `.env.example`
