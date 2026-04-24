# CHANGELOG

## Flow — Voice Dictation App

---

### 2026-04-24 — v0.2 WisprFlow-Inspired Improvements 🔧

**Reverse-engineered WisprFlow v1.5.55 and ported 5 key features.**

#### HotkeyManager Rewrite
- **`curKeysDown` set** — tracks ALL held keys (not just a bool for the hotkey)
- **`modifierKeysDown` set** — separate modifier state tracking
- **Stale key cleanup** — handles keys held before app start on first event
- **Tap resilience** — auto-restart event tap on disable, with retry count + max retries
- **Runtime hotkey update** — `updateCombo()` changes hotkey without full engine teardown

#### TextInjector Rewrite
- **`DelayedClipboardProvider`** — lazy NSPasteboardItemDataProvider (WisprFlow pattern)
  - Text isn't materialized until target app requests it during paste
  - More efficient, less clipboard manager flicker
- **Concealed clipboard type** — `org.nspasteboard.ConcealedType` marks data as sensitive
- **Failed paste detection** — timer-based detection with AX fallback tiers
- **Multi-tier paste fallback** — delayed provider → AX check → app activation → last resort
- **Paste result tracking** — `injectWithResult()` returns `.success`/`.failed`/`.blocked`

#### AppCoordinator
- Hotkey updates now use runtime `updateCombo()` instead of full engine teardown

#### DictationEngine
- `updateHotkey()` method for runtime hotkey changes
- Transcript handler uses new `PasteResult` for better error reporting

---

### 2026-04-22 — v0.1 WORKING PROTOTYPE 🎉

**Full end-to-end voice dictation working with ChatGPT subscription (no API key needed).**

#### Auth
- Reverse-engineered Codex CLI's exact OAuth PKCE flow
- Client ID: `app_EMoamEEZ73f0CkXaXp7hrann`
- Token exchange via form-urlencoded to `auth.openai.com`
- Subscription access token works on `api.openai.com/v1/realtime`

#### Realtime API
- WebSocket to `wss://api.openai.com/v1/realtime?model=gpt-realtime`
- Audio: PCM16 24kHz mono, base64 encoded via `input_audio_buffer.append`
- Commit buffer → `response.create` → transcript comes back
- Text injected via AppleScript `System Events` keystroke simulation

#### Audio Capture (the hard part)
- **Final solution: Core Audio `AudioDeviceCreateIOProcID`** — bypasses AVAudioEngine entirely
- AVAudioEngine was abandoned after 6+ failed attempts:
  - `outputFormat` lies about interleaving on some hardware
  - Taps at mismatched formats either crash (NSException) or silently never fire
  - Mixer nodes default to 44100Hz/2ch and don't pass through input data
- Core Audio IO proc works at any sample rate (24kHz, 48kHz) — no format negotiation
- Manual float32→int16 conversion + linear downsampling to 24kHz

#### Hotkey
- `ctrl+space` hold mode (press to talk, release to stop)

#### Known Issues
- Hardware sample rate randomly switches between 24kHz and 48kHz across sessions
- No floating pill UI yet (terminal only)
- No error recovery if WebSocket drops mid-session

---

### Architecture
```
Hotkey (ctrl+space) → DictationEngine → AudioCapture (Core Audio)
                                      → RealtimeClient (WebSocket, gpt-realtime)
                                      → TextInjector (AppleScript keystrokes)
                                      → ChatGPTAuth (OAuth PKCE, Codex client ID)
```
