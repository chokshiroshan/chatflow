# Flow v2 Changelog

All attempts, fixes, and outcomes tracked here so we stop going in circles.

## Auth Flow (RESOLVED ✅)

| Attempt | What changed | Result |
|---|---|---|
| 1 | Fake client ID `app_X8zY6vW2pQ9tR3dE7nK1jL5gH`, scope `model.request model.read` | ❌ "unknown_error" from OpenAI |
| 2 | Real Codex client ID `app_EMoamEEZ73f0CkXaXp7hrann`, Codex scope `api.connectors.read api.connectors.invoke`, `originator=flow_app` | ❌ "unknown_error" (wrong originator) |
| 3 | Fixed `originator=codex_cli_rs` | ✅ Auth consent page shows! But port 1455 in use |
| 4 | Kill stale process on port 1455, fallback to random port | ✅ Port bind works |
| 5 | Fixed double bind() bug — `waitForCallback()` was calling `startServer()` twice | ✅ **Auth works! Tokens received, refresh token saved** |

**Final working auth config:**
- Client ID: `app_EMoamEEZ73f0CkXaXp7hrann`
- Scope: `openid profile email offline_access api.connectors.read api.connectors.invoke`
- Extra params: `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, `originator=codex_cli_rs`
- PKCE: URL-safe base64 no-pad, S256 challenge
- Token exchange/refresh: form-urlencoded
- Callback: `http://localhost:1455/auth/callback`

## WebSocket Connection (RESOLVED ✅)

| Attempt | Endpoint | Result |
|---|---|---|
| 1 | `wss://api.openai.com/v1/realtime` + `OpenAI-Beta: realtime=v1` | Connected ✅ (with subscription token) |
| 2 | `wss://chatgpt.com/backend-api/codex/realtime` | ❌ Cloudflare blocks it (needs cookie handling Codex has via reqwest) |
| 3 | Back to `wss://api.openai.com/v1/realtime` | ✅ **Session created + configured** |

**Final working endpoint:** `wss://api.openai.com/v1/realtime?model=gpt-realtime` with subscription Bearer token.

## Audio Capture (IN PROGRESS ❌)

**Problem:** 0 chunks sent despite engine running and tap installed. Server says "buffer too small, 0.00ms of audio."

| Attempt | What changed | Result |
|---|---|---|
| 1 | Tap `mainMixerNode` with `mixerFormat` | ❌ Crash: setFormat error -10865 (format mismatch on tap) |
| 2 | Tap `inputNode` with its own `hardwareFormat`, convert after | ❌ No crash, but **0 chunks** — `processBuffer` never called or produces empty output |

**Known facts:**
- Hardware format: 48000.0Hz, 1 channel, `pcmFormatFloat32` (commonFormat rawValue: 1)
- Target format: 24000Hz, 1 channel, `pcmFormatInt16`, interleaved
- Engine starts successfully: "Engine started, capturing at 48000Hz"
- `processBuffer` either never fires or `outputBuffer.frameLength` is 0

**Next things to try (NOT YET TRIED):**
- [ ] Add debug print INSIDE `processBuffer` to see if tap callback fires at all
- [ ] Use `pcmFormatFloat32` for the tap format and convert manually
- [ ] Try tapping with `AVAudioFormat(standardFormatWithSampleRate:)` (non-interleaved float32)
- [ ] Try `bufferSize: 1024` instead of 4096
- [ ] Check if `AVAudioConverter` from float32→int16 + 48k→24k is actually working
- [ ] Try manual resampling: downsample 48k→24k by dropping every other sample
- [ ] Try `inputNode.installTap` with `nil` format (let it use default)

## End-to-End Dictation (BLOCKED by audio)

- Auth ✅
- WebSocket ✅ 
- Audio capture ❌ (0 chunks)
- Text injection (untested, blocked by audio)
