# 🎤 ChatFlow

Voice dictation for macOS, powered by your ChatGPT subscription.

Hold a hotkey, speak, release → text appears in any app. Lives in the menu bar.

**Enhanced mode:** Hold **Shift + hotkey** to capture screen context for better accuracy on technical terms.

---

## Install

### Option 1: DMG (recommended)

1. Download `ChatFlow.dmg` from [Releases](https://github.com/chokshiroshan/chatflow/releases)
2. Open the DMG
3. Drag **ChatFlow** to **Applications**
4. Right-click → Open on first launch (bypasses Gatekeeper)

### Option 2: Homebrew

```bash
brew install --cask chatflow
```

### Option 3: Build from source

```bash
git clone https://github.com/chokshiroshan/chatflow.git
cd chatflow

# Just the .app
./build.sh

# .app + DMG installer
./build.sh dmg

# Clean build artifacts
./build.sh clean
```

## First Launch

ChatFlow needs three macOS permissions:

1. **Microphone** — for voice capture
2. **Accessibility** — for global hotkey and text injection
3. **Input Monitoring** — for keyboard event handling

The onboarding flow walks you through all three. You'll also sign in with your ChatGPT account.

## Usage

| Action | What happens |
|---|---|
| **Hold Ctrl+Space** | Start recording. Release to transcribe + inject. |
| **Hold Ctrl+Shift+Space** | Enhanced mode — captures screen for context-aware transcription. |
| **Menu bar → Settings** | Change hotkey, sounds, sign-in, privacy info. |

## Features

- **Real-time transcription** via OpenAI Realtime API
- **Screen-aware mode** — screenshot + GPT-4o-mini vision for domain vocabulary
- **Works everywhere** — any text field in any app
- **Floating pill** — visual feedback while recording
- **Sound effects** — start/stop/success/error sounds
- **Auto-start at login** — optional
- **ChatGPT auth** — uses your existing subscription, no API key needed
- **Keychain storage** — tokens stored securely

## Architecture

```
Sources/Flow/
├── AppCoordinator.swift       # Central state management
├── FlowApp.swift              # SwiftUI app entry (menu bar only)
├── Auth/                      # ChatGPT OAuth PKCE authentication
├── Audio/                     # Mic capture (24kHz PCM16) + playback
├── Config/                    # Context & instruction building
├── Context/                   # Screen context extraction (vision API)
├── Hotkey/                    # CGEventTap global hotkey detection
├── Injection/                 # Text injection (clipboard Cmd+V)
├── Models/                    # FlowState, FlowConfig, AppState
├── Permissions/               # macOS permission management
├── Realtime/                  # WebSocket Realtime API + dictation engine
├── Startup/                   # Launch-at-login management
└── UI/                        # All SwiftUI views
    ├── Floating/              # Floating pill window controller
    ├── MenuView.swift         # Menu bar popover
    ├── SettingsView.swift     # Settings window
    ├── OnboardingView.swift   # First-launch setup flow
    └── DesignSystem.swift     # Colors, typography, radii
```

## Build Scripts

| Script | Purpose |
|---|---|
| `./build.sh` | Build .app bundle with entitlements |
| `./build.sh dmg` | Build .app + DMG installer |
| `./build.sh clean` | Remove all build artifacts |

## Requirements

- macOS 14+ (Sonoma)
- ChatGPT account (Plus/Pro/Team/Enterprise)
- Xcode Command Line Tools (for building from source)

## License

Private — for personal use.
