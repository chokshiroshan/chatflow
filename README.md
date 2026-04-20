# Flow 🎤💬

Voice dictation + voice chat for macOS, powered by ChatGPT's Realtime API.
**Included with your ChatGPT subscription — no extra cost.**

## Features

### 🎤 Dictation Mode
- Press **Fn** to talk, release to submit
- Text appears in whatever field you're typing in
- Works system-wide across all apps
- Streaming partial transcripts as you speak

### 💬 Voice Chat Mode
- Real-time voice conversation with ChatGPT
- Server-side voice activity detection (speak naturally)
- Hear ChatGPT respond in real-time audio
- Full conversation transcript shown

### 🔐 ChatGPT Authentication
- Sign in with your ChatGPT account (Plus, Pro, Team, etc.)
- No API key needed — uses your subscription
- Tokens stored securely in macOS Keychain

## Quick Start

```bash
# Build (requires macOS 14+ and Xcode)
cd flow
swift build -c release

# Run
.build/release/Flow
```

**First launch:**
1. Click the 🎤 icon in your menu bar
2. Click "Sign in with ChatGPT"
3. Log in via browser
4. Grant Accessibility + Microphone permissions when prompted
5. Press **Fn** to dictate — done!

## Modes

### Dictation (default)
Hold **Fn** → speak → release. Your words appear in the active text field.

Supports hold-to-talk and toggle modes (change in Settings).

### Voice Chat
Click "Start Voice Chat" in the menu. Speak naturally — ChatGPT hears you and responds with voice. Like a phone call with ChatGPT.

Choose from 6 voices in Settings: Alloy, Echo, Fable, Onyx, Nova, Shimmer.

## Permissions

Flow needs three permissions on macOS:

| Permission | Why | Where to grant |
|---|---|---|
| **Microphone** | Audio capture | System Settings → Privacy → Microphone |
| **Accessibility** | Text injection + global hotkey | System Settings → Privacy → Accessibility |
| **Input Monitoring** | Keystroke detection | System Settings → Privacy → Input Monitoring |

## Configuration

Settings are stored in `~/.flow/config.json`:

```json
{
  "hotkey": "fn",
  "hotkeyMode": "hold",
  "language": "en",
  "preferredMode": "Dictation",
  "voiceChatVoice": "alloy",
  "realtimeModel": "gpt-realtime-1.5",
  "injectMethod": "clipboard"
}
```

### Hotkey Options
`fn` (default), `rightcmd`, `rightopt`, `f5`, `f6`, `f7`, `f8`

### Supported Languages (Dictation)
English, Spanish, French, German, Japanese, Chinese, Korean, and 90+ more

## How It Works

```
┌─────────────────────────────────────────────┐
│                   Flow.app                   │
│                                              │
│  ┌──────────┐   ┌──────────┐   ┌─────────┐ │
│  │  Hotkey   │   │  Audio   │   │  Text   │ │
│  │ (Fn key)  │   │ Capture  │   │Injector │ │
│  │ CGEventTap│   │24kHz PCM │   │ AX/Clip │ │
│  └─────┬─────┘   └─────┬────┘   └────▲────┘ │
│        │               │              │       │
│        ▼               ▼              │       │
│  ┌──────────────────────────────┐     │       │
│  │     RealtimeClient           │     │       │
│  │  wss://api.openai.com/...    │     │       │
│  │  • Dictation: text output    │─────┘       │
│  │  • Voice Chat: audio+text    │             │
│  └──────────────────────────────┘             │
│                     ▲                         │
│  ┌──────────────────┴──────────────────┐      │
│  │         ChatGPTAuth                 │      │
│  │  OAuth PKCE → auth0.openai.com     │      │
│  │  Tokens → macOS Keychain           │      │
│  └────────────────────────────────────┘      │
└─────────────────────────────────────────────┘
```

## Building with Xcode

For proper code signing and entitlements (recommended for daily use):

1. Open Xcode → File → New → Project → macOS → App
2. Copy all files from `Sources/Flow/` into the project
3. Add `Info.plist` and `Flow.entitlements`
4. Set signing team to your Apple ID
5. Build & run

Without code signing, Accessibility permissions won't persist across launches.

## License

MIT
