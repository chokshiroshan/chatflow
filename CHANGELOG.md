# CHANGELOG

## Flow — Voice Dictation App

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
