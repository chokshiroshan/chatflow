import Foundation

/// Dictation engine — buffers audio and transcribes via Whisper API.
///
/// Flow:
/// 1. On activate: pre-connect to ensure token is valid
/// 2. Hotkey pressed → start audio capture (instant)
/// 3. Audio chunks buffered in memory
/// 4. Hotkey released → send buffered audio to Whisper API
/// 5. Inject transcript into focused text field
///
/// Auth: ChatGPT subscription token (same OAuth flow as before)
/// STT: whisper-1 via /v1/audio/transcriptions (dedicated STT, not gpt-realtime)
@MainActor
final class DictationEngine {
    var onStateChanged: ((FlowState) -> Void)?
    var onPartialTranscript: ((String) -> Void)?

    private let auth: ChatGPTAuth
    private let config: FlowConfig
    private let audioCapture = AudioCapture()
    private let hotkey: HotkeyManager
    private var audioBuffer = Data()
    private var isRecording = false

    init(auth: ChatGPTAuth, config: FlowConfig) {
        self.auth = auth
        self.config = config

        self.hotkey = HotkeyManager(key: config.hotkey, mode: config.hotkeyMode)
        self.hotkey.onStart = { [weak self] in Task { @MainActor in await self?.startDictation() } }
        self.hotkey.onStop = { [weak self] in Task { @MainActor in await self?.finishDictation() } }
    }

    func activate() {
        hotkey.start()
        onStateChanged?(.idle)
        print("🎤 Dictation active. Press \(config.hotkey) to start.")

        // Validate token on startup
        Task {
            if let token = await auth.ensureValidToken() {
                _ = token
                print("✅ Token valid — ready to dictate")
            }
        }
    }

    func deactivate() {
        hotkey.stop()
        audioCapture.stop()
        isRecording = false
    }

    // MARK: - Dictation Lifecycle

    private func startDictation() async {
        guard !isRecording else {
            print("⚠️ Already recording — forcing stop first")
            await finishDictation()
            return
        }

        // Ensure we have a valid token
        guard let token = await auth.ensureValidToken() else {
            print("⚠️ No valid token — please sign in again")
            onStateChanged?(.error("Session expired. Please sign in again."))
            return
        }
        _ = token

        audioBuffer = Data()
        isRecording = true
        onPartialTranscript?("")

        // Wire audio callback — just buffer the PCM16 data
        audioCapture.onAudioData = { [weak self] data in
            self?.audioBuffer.append(data)
        }

        do {
            try audioCapture.start()
            onStateChanged?(.recording)
            print("🎙️ Recording started")
        } catch {
            print("⚠️ Audio capture failed: \(error)")
            onStateChanged?(.error("Audio capture failed: \(error.localizedDescription)"))
            isRecording = false
        }
    }

    private func finishDictation() async {
        guard isRecording else { return }
        isRecording = false

        audioCapture.stop()
        let audioData = audioBuffer
        audioBuffer = Data()

        let chunkSize = 4800 // ~100ms at 24kHz PCM16 = 4800 bytes
        let chunkCount = audioData.count / chunkSize
        print("🛑 Recording stopped (\(audioData.count) bytes, ~\(chunkCount) chunks)")

        // Need at least 100ms of audio
        guard audioData.count >= chunkSize else {
            print("⚠️ Audio too short (<100ms) — skipping")
            onStateChanged?(.idle)
            return
        }

        onStateChanged?(.processing)

        // Transcribe via Whisper API
        guard let token = auth.accessToken else {
            onStateChanged?(.error("No access token"))
            return
        }

        do {
            let whisper = WhisperClient(
                accessToken: token,
                model: "whisper-1",
                language: config.language
            )

            let text = try await whisper.transcribe(pcm16Data: audioData, sampleRate: 24000)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("⚠️ Empty transcript — no speech detected")
                onStateChanged?(.idle)
                return
            }

            // Inject text
            onStateChanged?(.injecting)
            let success = TextInjector.inject(text)
            print(success ? "✅ Text injected" : "❌ Text injection failed")
            onStateChanged?(success ? .idle : .error("Text injection failed"))

        } catch {
            print("❌ Transcription failed: \(error)")
            onStateChanged?(.error("Transcription failed: \(error.localizedDescription)"))
        }
    }
}
