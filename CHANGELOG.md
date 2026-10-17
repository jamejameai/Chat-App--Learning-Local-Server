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

## [Phase 1] - 2026-10-17
### Added
- Native iOS Foundation:
  - Standard Xcode project (`ios/MiniTelegram.xcodeproj`) generated via `xcodegen`.
  - Design Tokens (`AppColors`, `AppSpacing`, `AppCornerRadius`, `AppTypography`).
  - Reusable components (`PrimaryButton`, `CustomTextField`, `LoadingView`, `EmptyStateView`, `ErrorStateView`, `AvatarView`).
  - Bilingual localization (`en.lproj/Localizable.strings`, `km.lproj/Localizable.strings`) and `LocalizationManager` with dynamic runtime language switching.
  - Core Navigation: `MainTabView` (Chats, Calls, Groups, Settings) and `WelcomeView` (invite verification, account creation).
  - AppState & AppContainer dependency injection hub.
  - iOS Unit Test Suite: `AppStateTests`, `LocalizationTests` (`** TEST SUCCEEDED **` with 0 failures).
- Backend Monolith Foundation (`server/`):
  - NestJS modular architecture with TypeScript and strict DTO validation pipes.
  - Database pool & transaction management (`DatabaseService`) on PostgreSQL 16.
  - Initial database migration `001_initial_schema.sql` (12 relational tables with constraints & indexes).
  - Standalone migration runner (`migrate.ts`).
  - Health check endpoint `GET /api/v1/health` (DB & encrypted storage health).
  - Auth, Invitations, Devices, Conversations, Messages, and Realtime WebSocket modules.
- Infrastructure:
  - Turnkey `infrastructure/docker-compose.yml` for PostgreSQL 16, Caddy 2, LiveKit SFU, and Coturn TURN relay.
  - `infrastructure/reverse-proxy/Caddyfile`, `infrastructure/coturn/turnserver.conf`, `infrastructure/livekit.yaml`.
