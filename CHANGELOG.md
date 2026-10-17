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

## [Phase 2] - 2026-10-17
### Added
- Identity & Invitation-Only Access Subsystem:
  - Backend invitation service (`/invitations/validate`, `/invitations`, `/invitations/:id/revoke`) with role validation (`superadmin`, `member`) and single-use expiry tracking.
  - Multi-device registration endpoint (`/devices/register`, `/devices/list`, `/devices/:id`) storing identity public keys, signed prekeys, and one-time prekeys.
  - Device revocation endpoint with session invalidation and audit trail.
  - Database bootstrap migration `002_bootstrap_superadmin.sql` for initial super-admin deployment.
  - iOS `AuthViewModel` orchestrating invitation validation, biometric/keychain integration, and authenticated sessions.
  - iOS `AccountSetupView` with animated cryptographic key generation and role badge presentation.
  - iOS `SettingsView` displaying user profile, active device fingerprint, E2EE verification status, and biometric lock.
  - iOS `DeviceManagementView` for active device inspection and remote revocation with user confirmation.
  - iOS `SuperAdminInvitationsView` with code generation, role selector, expiry configuration, and clipboard export.
  - Unit Tests: `AuthService` test suite verifying invitation rejection (expired, revoked, redeemed, nonexistent) and password validation (10/10 tests passed).

## [Phase 3] - 2026-10-17
### Added
- End-to-End Encryption (E2EE) Cryptographic Foundation:
  - `CryptoIdentityService`: Curve25519 DH key generation, Ed25519 signing key generation, signed prekeys with cryptographic signature verification, and 50 one-time prekeys (OPKs) batch generation.
  - `DoubleRatchetEngine`: Full Signal Double Ratchet protocol implementation including KDF-RK, KDF-CK, symmetric ratchet, Diffie-Hellman ratchet step, and out-of-order skipped message key recovery cache (up to 2,000 keys).
  - `X3DHEngine`: Extended Triple Diffie-Hellman key agreement (DH1, DH2, DH3, optional DH4) deriving 256-bit master shared secrets with Ed25519 identity signature verification.
  - `SenderKeysEngine`: Sender Key protocol for multi-party group encryption with forward secrecy and deterministic member re-keying on membership revocation.
  - `FileEncryptionService`: Zero-knowledge streaming file encryption using AES-256-GCM and SHA-256 integrity checksums for encrypted attachment transfer.
  - `KeychainManager`: Hardware-backed Secure Enclave / iOS Keychain wrapper for persistent private keys, biometric access control, and token management.
  - `BiometricAuthManager`: LocalAuthentication framework integration supporting Face ID, Touch ID, and device passcode fallbacks.
  - Verified Cryptographic Unit Tests: Full passing test suite (`DoubleRatchetTests`, `X3DHTests`, `SenderKeysTests`, `CryptoIdentityTests`, `FileEncryptionTests`) executing 16 tests with 0 failures on iOS Simulator.

## [Phase 4] - 2026-10-17
### Added
- Persistent Encrypted Messaging & Realtime Gateway:
  - Backend messaging service (`MessagesService`) with atomic monotonic sequence allocation (`UPDATE conversations SET last_sequence_id = last_sequence_id + 1 ... RETURNING last_sequence_id`) ensuring linear message order.
  - Message deduplication & client UUID idempotency preventing replay duplication.
  - Realtime WebSocket gateway (`RealtimeGateway`) broadcasting `message.new`, `message.receipt`, `typing.update`, and `presence.update`.
  - Delivery and read receipts endpoint (`POST /conversations/:id/messages/:messageId/receipt`) with automatic sequence marker updating on `conversation_members`.
  - Team member directory endpoint (`GET /auth/users`) with search query filtering.
  - iOS `LocalDatabaseManager`: file-backed encrypted local message persistence with automatic sequence sorting, deduplication, unread counting, and full-text search across decrypted text.
  - iOS `MessageCryptoCoordinator`: coordinator wrapping Double Ratchet and AEAD payload encryption, serialization, and inner payload decoding (text, replies, reactions).
  - iOS `RealtimeService`: Socket.IO / WebSocket client with automatic exponential backoff reconnection, heartbeat ping/pong, presence, and typing status dispatch.
  - iOS UI:
    - `ConversationListView`: responsive conversation list, unread badges, timestamp formatting, online indicators, and instant local full-text search.
    - `NewConversationSheet`: team directory selector to launch 1:1 direct encrypted chats.
    - `ChatDetailView`: chat room with date separator headers, message bubbles, scrolling reader, delivery/read tick indicators, and live typing subtitle.
    - `MessageBubbleView`: native chat bubbles with custom corner geometry, quoted reply preview, timestamp, status ticks (sending, sent, delivered, read), context menu, and interactive emoji reaction ribbons.
    - `MessageComposerView`: multi-line expanding input, quoted reply banner with cancel button, attachment action, and animated send button.
  - Verified Unit Tests: 6 new unit tests (`MessagingTests`) verifying local database sorting, idempotency, full-text search, reaction mutations, read receipt tracking, and cryptographic envelope round-tripping. Total iOS suite: 22/22 tests passing with 0 failures. Server test suite: 10/10 tests passing with 0 failures.
