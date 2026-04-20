# Flow — Build & Development Guide

## Project Structure

```
Flow/
├── Package.swift                          # SwiftPM config
├── build.sh                               # Build script
├── README.md
├── Sources/Flow/
│   ├── main.swift                         # CLI entry point (ArgumentParser)
│   ├── FlowManager.swift                  # State machine + central coordinator
│   ├── Hotkey/
│   │   └── HotkeyManager.swift            # CGEventTap global hotkey (167 lines)
│   ├── Audio/
│   │   └── AudioCapture.swift             # AVAudioEngine → 24kHz mono PCM (124 lines)
│   ├── Injection/
│   │   └── TextInjector.swift             # AXUI → CGEvent → Clipboard chain (203 lines)
│   ├── Transcription/
│   │   ├── TranscriptionService.swift     # Protocol definition
│   │   ├── RealtimeClient.swift           # OpenAI Realtime WebSocket API (261 lines)
│   │   └── GroqClient.swift              # Groq Whisper (free tier) fallback (161 lines)
│   ├── Auth/
│   │   └── ChatGPTAuth.swift             # ChatGPT backend OAuth (experimental)
│   └── UI/
│       └── StatusBar.swift                # Menu bar indicator
└── Resources/Sounds/
```

**Total: ~1,400 lines of Swift**

## How It Works

### 1. Global Hotkey (CGEventTap)
- Registers a `CGEventTap` on the CGSession for keyDown/keyUp/flagsChanged events
- Fn key (keyCode 63) is the default trigger
- Supports hold-to-talk (press to record, release to submit) and toggle modes
- Requires Input Monitoring permission

### 2. Audio Capture (AVAudioEngine)
- Taps the input node on `AVAudioEngine` at hardware sample rate (48kHz on Apple Silicon)
- Resamples to 24kHz mono float32 PCM via `AVAudioConverter`
- Buffers are streamed to the transcription service in real-time
- The Realtime API expects base64-encoded PCM16 (we convert float32 → int16)

### 3. Transcription (Two Backend Options)

**Option A: OpenAI Realtime API** (RealtimeClient.swift)
- Connects via WebSocket to `wss://api.openai.com/v1/realtime?model=gpt-realtime-1.5`
- Sends audio via `input_audio_buffer.append` events
- Receives streaming transcripts via `conversation.item.input_audio_transcription.delta`
- Also gets model-generated text via `response.text.delta` events
- Session configured with `input_audio_transcription: { model: "whisper-1" }` for STT
- Cost: ~$0.06/min via API, or free via ChatGPT backend (experimental)

**Option B: Groq Whisper** (GroqClient.swift) — **RECOMMENDED FOR FREE USAGE**
- Buffers all audio, sends as WAV to `https://api.groq.com/openai/v1/audio/transcriptions`
- Uses `whisper-large-v3-turbo` model
- Generous free tier — practically unlimited for personal dictation
- Latency: ~200-500ms (no streaming, but fast)
- Get key at: https://console.groq.com/keys

### 4. Text Injection (Three-Tier Fallback)
1. **AXUIElement** — Find focused text field, set value directly. Fast but doesn't work everywhere.
2. **CGEvent keystrokes** — Type each character. Universal but slow.
3. **Clipboard paste** (default) — Write to NSPasteboard, simulate Cmd+V, restore clipboard. Most reliable.

### 5. State Machine
```
idle → recording → processing → injecting → idle
  ↑                                   ↓
  └─────────── error ←────────────────┘
```

## Next Steps / TODO

### POC → Production
- [ ] Fix CommonCrypto import for ChatGPTAuth (needs proper bridging on macOS)
- [ ] Add local HTTP callback server for PKCE auth flow
- [ ] Test on actual macOS hardware
- [ ] Add sound effects (start/stop recording beeps)
- [ ] Add floating pill UI (not just menu bar)

### Progressive Paste (Wispr Flow's Secret)
- [ ] Add local Whisper (via WhisperKit or whisper.cpp) for instant first-pass transcription
- [ ] Send to cloud for LLM refinement
- [ ] Silently replace text if cloud version differs
- This gives ~200ms perceived latency

### ChatGPT Backend Auth
- [ ] Reverse engineer exact OAuth scopes Codex requests
- [ ] Implement local callback server for auth code exchange
- [ ] Test backend-api/realtime/calls endpoint
- [ ] Handle token refresh automatically
- [ ] Store tokens in macOS Keychain

### Polish
- [ ] Xcode project with proper entitlements
- [ ] Code signing (needed for Accessibility permissions to stick)
- [ ] Auto-update (Sparkle framework)
- [ ] Custom vocabulary (like Wispr Flow)
- [ ] App-specific formatting (casual for Slack, formal for email)

## Testing on Your Mac

1. Clone the project
2. `cd flow && swift build -c release`
3. Get a Groq API key (free): https://console.groq.com/keys
4. `export GROQ_API_KEY=gsk_...`
5. `./build.sh` or `.build/release/Flow`
6. Grant Accessibility + Microphone permissions when prompted
7. Open any text field, press Fn key, speak, release
