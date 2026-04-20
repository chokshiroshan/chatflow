# 🎤💬 Flow

Voice dictation + voice chat for macOS, powered by your ChatGPT subscription.

**Two modes:**
- **🎤 Dictation** — Press Fn, speak, release → text appears in any app
- **💬 Voice Chat** — Click to start → real-time voice conversation with ChatGPT

Zero dependencies. Pure Swift + Apple frameworks.

---

## Quick Start (Xcode)

```bash
git clone https://github.com/chokshiroshan/chatflow.git
cd chatflow
open Package.swift
```

Then in Xcode:
1. Select **Flow** scheme → **My Mac**
2. **Product → Run** (⌘R)
3. Grant permissions when prompted (mic, accessibility, input monitoring)
4. Sign in with your ChatGPT account in the web view
5. Press **Fn** to dictate, or click **Start Voice Chat** from the menu bar

## Why Xcode?

`swift run` works but **won't have proper entitlements** — no mic access, no global hotkeys, no text injection. You need Xcode for:
- Microphone access
- Accessibility API (text injection)
- Input monitoring (global hotkeys)
- Proper app signing

## Building from Terminal

If you just want to verify it compiles:
```bash
swift build
```

## Features

| Feature | Status |
|---|---|
| Dictation mode (Fn → text in any app) | ✅ |
| Voice chat mode (real-time conversation) | ✅ |
| ChatGPT login via web view | ✅ |
| Backend-api path (free with subscription) | ✅ |
| Developer API fallback (OPENAI_API_KEY) | ✅ |
| Groq Whisper free fallback | ✅ |
| Floating pill overlay | ✅ |
| Sound effects | ✅ |
| Permissions onboarding | ✅ |
| Auto-start at login | ✅ |
| 6 voice options | ✅ |
| 10+ languages | ✅ |
| Keychain token storage | ✅ |

## API Priority

Flow tries multiple backends in order:

1. **ChatGPT backend-api** — Free with your subscription. Uses your login session.
2. **OpenAI Realtime API** — Requires `OPENAI_API_KEY` env var. Pay-per-use.
3. **Groq Whisper** — Free tier. Transcription only (no voice chat). Requires `GROQ_API_KEY` env var.

## Configuration

All settings accessible from the menu bar → Settings:
- Hotkey (Fn, Right ⌘, Right ⌥, F5-F8)
- Mode (hold-to-talk or toggle)
- Text injection method (clipboard, accessibility, keystrokes)
- Voice (Alloy, Echo, Fable, Onyx, Nova, Shimmer)
- Language (10+ languages)
- Auto-start at login

Config stored at `~/.flow/config.json`.

## Architecture

```
Sources/Flow/
├── AppCoordinator.swift      # Wires all subsystems
├── FlowApp.swift              # SwiftUI app entry point
├── Auth/                      # ChatGPT authentication
│   ├── ChatGPTAuth.swift      # Web view login + token capture
│   ├── KeychainStore.swift    # Secure token storage
│   └── OAuthCallbackServer.swift
├── Audio/                     # Audio capture & playback
│   ├── AudioCapture.swift     # Mic → 24kHz PCM16
│   └── AudioPlayer.swift      # PCM16 → speakers
├── Hotkey/                    # Global hotkey detection
│   └── HotkeyManager.swift    # CGEventTap-based
├── Injection/                 # Text injection into apps
│   └── TextInjector.swift     # Clipboard / AXUI / keystrokes
├── Models/                    # Data models
│   └── AppState.swift         # FlowState, FlowConfig, etc.
├── Permissions/               # macOS permission management
│   └── PermissionsManager.swift
├── Realtime/                  # API clients
│   ├── RealtimeClient.swift   # WebSocket Realtime API
│   ├── ChatGPTBackendClient.swift  # backend-api path
│   ├── DualPathClient.swift   # Orchestrates API fallback chain
│   ├── DictationEngine.swift  # Dictation mode logic
│   ├── VoiceChatEngine.swift  # Voice chat mode logic
│   └── GroqFallback.swift     # Free Groq Whisper fallback
├── Startup/                   # Auto-start management
│   └── AutoStartManager.swift
└── UI/                        # SwiftUI views
    ├── MenuView.swift         # Menu bar popover
    ├── VoiceChatView.swift    # Voice chat window
    ├── SettingsView.swift     # Settings window
    ├── OnboardingView.swift   # First-launch permissions
    ├── FloatingPill.swift     # Translucent overlay
    └── SoundManager.swift     # System sound effects
```

## License

Private — for personal use.
