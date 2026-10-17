# Mini Telegram — Development Environment & Workflow

## 1. Quick Start

### 1.1 Prerequisites
- **macOS** with Apple Silicon (recommended for iOS simulator and Docker performance).
- **Xcode 16+** (with iOS 18+ / 27+ simulator installed).
- **Node.js 20+** (v24.x tested) and **npm 10+**.
- **Docker Desktop** or Colima / OrbStack.

### 1.2 Repository Structure
```
mini-telegram/
├── ios/            # Native Swift / SwiftUI iOS application
├── server/         # NestJS backend modular monolith
├── infrastructure/ # Docker compose, reverse-proxy, TURN, scripts
├── docs/           # Technical specifications & architecture guides
├── .env.example    # Configuration template
├── README.md       # Project overview
└── CHANGELOG.md    # Development log
```

---

## 2. Backend Development Workflow

```bash
cd server
npm install

# Run database & dependencies in background
docker compose -f ../infrastructure/docker-compose.yml up -d postgres livekit coturn

# Run database migrations
npm run migration:run

# Start backend in development watch mode
npm run start:dev

# Run automated unit and integration tests
npm test
```

---

## 3. iOS Development Workflow

1. Open `ios/MiniTelegram.xcodeproj` in Xcode (or use Swift Package / command line tools).
2. Select an iOS Simulator (e.g. `iPhone 18 Pro` or `iPhone 17`).
3. Press `Cmd + B` to build, or `Cmd + R` to run.
4. Execute unit and UI tests with `Cmd + U` or via `xcodebuild test`:
```bash
xcodebuild test \
  -project ios/MiniTelegram.xcodeproj \
  -scheme MiniTelegram \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

---

## 4. Coding Standards & Review Gates

1. **Zero Secret Logging**: Never log passwords, tokens, private keys, or decrypted message plaintext.
2. **Swift Concurrency**: Favor `async/await` and actors over completion handlers and manual locks.
3. **Localization**: Never hardcode English strings directly in SwiftUI view bodies; use `AppStrings` or `LocalizedStringKey`.
4. **TypeScript Strictness**: NestJS controllers, services, and DTOs must use strict typing with `class-validator` decorators.
