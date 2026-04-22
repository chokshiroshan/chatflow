import Foundation

/// Direct Whisper API client for high-accuracy speech-to-text.
///
/// Uses OpenAI's /v1/audio/transcriptions endpoint with whisper-1 model.
/// Works with ChatGPT subscription tokens (same as Realtime API path).
///
/// Compared to Realtime API transcription:
/// - ✅ Much better accuracy (dedicated STT model, not conversational)
/// - ✅ Punctuation, capitalization, paragraph breaks built-in
/// - ✅ Supports prompt parameter for context/correct spellings
/// - ❌ No streaming (batch: send audio, wait for full transcript)
/// - ❌ Slightly higher latency for long audio
final class WhisperClient {
    private let accessToken: String
    private let model: String
    private let language: String

    var onPartialTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?

    init(accessToken: String, model: String = "whisper-1", language: String = "en") {
        self.accessToken = accessToken
        self.model = model
        self.language = language
    }

    /// Transcribe PCM16 audio data via Whisper API.
    /// - Parameters:
    ///   - pcm16Data: Raw PCM16 audio at 24kHz mono
    ///   - sampleRate: Sample rate of the audio (default 24000)
    ///   - prompt: Optional prompt to guide transcription style/spellings
    func transcribe(pcm16Data: Data, sampleRate: Int = 24000, prompt: String? = nil) async throws -> String {
        // Convert PCM16 → WAV (Whisper needs a proper audio format)
        let wavData = Self.pcm16ToWav(pcm16Data, sampleRate: sampleRate, channels: 1)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append(model)
        body.append("\r\n".data(using: .utf8)!)

        // Language field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append(language)
        body.append("\r\n".data(using: .utf8)!)

        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json")
        body.append("\r\n".data(using: .utf8)!)

        // Optional prompt for better accuracy
        if let prompt {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append(prompt)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("📤 Sending \(pcm16Data.count) bytes PCM16 (\(wavData.count) bytes WAV) to Whisper API...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        guard httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            print("❌ Whisper API error (\(httpResp.statusCode)): \(body)")
            throw WhisperError.apiError("Whisper API error (\(httpResp.statusCode)): \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let text = json["text"] as? String ?? ""

        print("📝 Whisper transcript: \"\(text)\"")
        return text
    }

    // MARK: - WAV Encoding

    /// Convert raw PCM16 data to WAV format with proper headers.
    static func pcm16ToWav(_ pcm16: Data, sampleRate: Int, channels: Int) -> Data {
        let byteRate = sampleRate * channels * 2  // 16-bit = 2 bytes
        let blockAlign = channels * 2
        let dataSize = pcm16.count
        let fileSize = 36 + dataSize

        var wav = Data(capacity: 44 + dataSize)

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM format
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })   // bits per sample

        // data chunk
        wav.append(contentsOf: "data".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        wav.append(pcm16)

        return wav
    }
}

enum WhisperError: LocalizedError {
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Whisper API"
        case .apiError(let msg): return msg
        }
    }
}
