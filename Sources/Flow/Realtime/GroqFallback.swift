import Foundation

/// Free transcription fallback using Groq's Whisper API.
///
/// Groq offers a generous free tier for whisper-large-v3-turbo.
/// Use this when the ChatGPT Realtime API is unavailable.
///
/// Limitations vs Realtime API:
/// - No streaming (batch transcription after recording ends)
/// - No voice chat (text output only)
/// - ~200-500ms latency (still fast)
///
/// Get free API key: https://console.groq.com/keys
final class GroqWhisperClient {
    var onFinalTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let apiKey: String
    private var audioBuffer = Data()

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Buffer audio chunks during recording.
    func appendAudio(_ pcm16Data: Data) {
        audioBuffer.append(pcm16Data)
    }

    /// Send buffered audio for transcription. Call when recording ends.
    func transcribe(language: String = "en") async {
        guard !audioBuffer.isEmpty else {
            onError?("No audio recorded")
            return
        }

        let audio = audioBuffer
        audioBuffer = Data()

        do {
            let text = try await sendToGroq(audio: audio, language: language)
            onFinalTranscript?(text)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func reset() {
        audioBuffer = Data()
    }

    // MARK: - API Call

    private func sendToGroq(audio: Data, language: String) async throws -> String {
        // Convert PCM16 → WAV (add header)
        let wav = Self.pcm16ToWav(audio, sampleRate: 24000, channels: 1)

        let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "groq-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // File
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        body.append("\r\n")
        // Model
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("whisper-large-v3-turbo\r\n")
        // Language
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.append("\(language)\r\n")
        // Response format
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.append("json\r\n")
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw GroqError.apiError(body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw GroqError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - WAV Encoding

    private static func pcm16ToWav(_ pcm: Data, sampleRate: Int, channels: Int) -> Data {
        let dataSize = Int32(pcm.count)
        let fileSize = dataSize + 36
        let byteRate = Int32(sampleRate * channels * 2)
        let blockAlign = Int16(channels * 2)

        var wav = Data(capacity: pcm.count + 44)
        // RIFF header
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        wav.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        // fmt
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        wav.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) }) // PCM
        wav.append(contentsOf: withUnsafeBytes(of: Int16(channels).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: Int16(16).littleEndian) { Array($0) })
        // data
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        wav.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        wav.append(pcm)
        return wav
    }
}

enum GroqError: LocalizedError {
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "Groq API error: \(msg)"
        case .parseError: return "Could not parse transcription"
        }
    }
}
