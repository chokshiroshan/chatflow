import Foundation
import Testing
#if canImport(CommonCrypto)
import CommonCrypto
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Realtime API Stress Test
//
// Tests how far OpenAI lets us push free Realtime API usage.
// Streams synthetic audio (silence + tone bursts) and logs every
// rate_limits.updated event to build a complete limit profile.
//
// Usage (from ChatFlow project root on Mac Mini):
//   swift test --filter RealtimeStressTest
//
// Or standalone:
//   swift run RealtimeStressTest
//
// Requires: authenticated ChatGPT session in Keychain (sign in via Flow app first)

// MARK: - Config

struct StressTestConfig: Sendable {
    let accessToken: String
    let model: String = "gpt-realtime"
    let language: String = "en"
    /// Total test duration in seconds (0 = unlimited until failure)
    var maxDurationSeconds: Double = 0
    /// How long each "utterance" lasts (seconds of audio per commit)
    var utteranceDurationSeconds: Double = 8.0
    /// Gap between utterances (seconds)
    var interUtteranceGap: Double = 2.0
    /// Generate tone bursts instead of silence (better for testing transcription)
    var useToneBursts: Bool = true
    /// Tier label ("free", "plus", or "" for untagged) — used in output filenames
    var tier: String = ""
    /// Worker index (0 = solo run; >0 disambiguates parallel processes)
    var workerIndex: Int = 0
    /// Log file path
    let logPath: String

    /// Build a tier+worker-aware suffix, e.g. "-free", "-plus-w2", or ""
    var fileSuffix: String {
        var s = ""
        if !tier.isEmpty { s += "-\(tier)" }
        if workerIndex > 0 { s += "-w\(workerIndex)" }
        return s
    }

    /// Output paths
    var resultsPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flow/stress-test-results\(fileSuffix).json")
            .path
    }

    static func defaultLogPath(suffix: String = "") -> String {
        let ts = ISO8601DateFormatter().string(from: Date()).prefix(19)
            .replacingOccurrences(of: ":", with: "-")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flow/stress-test\(suffix)-\(ts).log")
            .path
    }

    /// Build a config from environment variables (used by both swift test + standalone runner).
    static func fromEnv(token: String) -> StressTestConfig {
        let env = ProcessInfo.processInfo.environment
        let tier = env["FLOW_STRESS_TIER"] ?? ""
        let worker = Int(env["FLOW_STRESS_WORKER"] ?? "0") ?? 0
        let aggressive = (env["FLOW_STRESS_AGGRESSIVE"] ?? "0") == "1"
        let duration = Double(env["FLOW_STRESS_DURATION"] ?? "0") ?? 0
        var cfg = StressTestConfig(
            accessToken: token,
            logPath: defaultLogPath(suffix: {
                var s = ""
                if !tier.isEmpty { s += "-\(tier)" }
                if worker > 0 { s += "-w\(worker)" }
                return s
            }())
        )
        cfg.tier = tier
        cfg.workerIndex = worker
        cfg.maxDurationSeconds = duration
        if aggressive {
            // Hammer mode: longer utterances, no gap.
            cfg.utteranceDurationSeconds = 15.0
            cfg.interUtteranceGap = 0.0
        }
        return cfg
    }
}

// MARK: - Rate Limit Event

struct RateLimitSnapshot: Codable, Sendable {
    let timestamp: Date
    let sessionIndex: Int
    let remainingRequests: Int?
    let remainingTokens: Int?
    let totalRequests: Int?
    let totalTokens: Int?
    let resetRequestsMs: Double?
    let resetTokensMs: Double?
    let rawJSON: String

    var elapsedSinceTestStart: Double? = nil
}

// MARK: - Test Results

struct StressTestResults: Codable {
    let startedAt: Date
    var endedAt: Date?
    var totalSessions: Int = 0
    var totalAudioSeconds: Double = 0
    var totalTokensConsumed: Int = 0
    var totalRequestsUsed: Int = 0
    var errors: [String] = []
    var rateLimitSnapshots: [RateLimitSnapshot] = []
    var sessionDurations: [Double] = []  // seconds per WS session
    var hardLimitHit: Bool = false
    var hardLimitMessage: String?
    var wsDisconnectCount: Int = 0
    var firstErrorAfterSession: Int?  // which session index first errored
    var peakTokensPerMinute: Int = 0
    var peakRequestsPerMinute: Int = 0

    var summary: String {
        let duration = endedAt.map { $0.timeIntervalSince(startedAt) } ?? 0
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return """
        ══════════════════════════════════════════════════
        🧪 STRESS TEST RESULTS
        ══════════════════════════════════════════════════
        Duration: \(mins)m \(secs)s
        Total WS sessions: \(totalSessions)
        Total audio streamed: \(String(format: "%.1f", totalAudioSeconds))s
        Total tokens consumed: \(totalTokensConsumed)
        Total requests used: \(totalRequestsUsed)
        WS disconnects: \(wsDisconnectCount)
        Hard limit hit: \(hardLimitHit ? "YES ❌" : "NO ✅")
        \(hardLimitMessage.map { "Limit message: \($0)" } ?? "")
        First error at session: \(firstErrorAfterSession.map { "#\($0)" } ?? "none")
        Peak tokens/min: \(peakTokensPerMinute)
        Peak requests/min: \(peakRequestsPerMinute)
        Rate limit snapshots: \(rateLimitSnapshots.count)
        Errors: \(errors.count)
        ══════════════════════════════════════════════════
        """
    }
}

// MARK: - Audio Generator

enum AudioGenerator {
    /// Generate PCM16 24kHz mono audio data.
    /// - silence: zero-filled buffer
    /// - toneBurst: 440Hz sine wave bursts with silence gaps (mimics speech patterns)
    static func generatePCM16(durationSeconds: Double, sampleRate: Double = 24000.0, mode: Bool = true) -> Data {
        let frameCount = Int(durationSeconds * sampleRate)
        var data = Data(capacity: frameCount * 2)

        for i in 0..<frameCount {
            let sample: Int16
            if mode {
                // Tone burst pattern: 0.5s tone + 0.3s silence, repeating
                let phase = Double(i) / sampleRate
                let cyclePos = phase.truncatingRemainder(dividingBy: 0.8)
                if cyclePos < 0.5 {
                    // 440Hz sine at ~20% volume
                    let t = Double(i) / sampleRate
                    let val = sin(2.0 * .pi * 440.0 * t) * 0.2
                    sample = Int16(val * 32767.0)
                } else {
                    sample = 0  // silence
                }
            } else {
                sample = 0  // pure silence
            }
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        return data
    }

    /// Split audio data into chunks matching what AudioCapture would produce (~480 samples @ 24kHz = 20ms)
    static func chunkAudio(_ data: Data, chunkSize: Int = 960) -> [Data] {
        // chunkSize = 960 bytes = 480 samples of Int16 = 20ms @ 24kHz
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }
}

// MARK: - Stress Test WebSocket Client

@MainActor
final class StressTestClient {
    private var webSocket: URLSessionWebSocketTask?
    private(set) var isConnected = false
    private var results: StressTestResults
    private let config: StressTestConfig
    private let logFile: FileHandle?
    private var sessionStart: Date?
    private var testStart: Date

    // Callbacks
    var onRateLimit: ((RateLimitSnapshot) -> Void)?
    var onError: ((String) -> Void)?
    var onTranscript: ((String) -> Void)?
    var onSessionComplete: (() -> Void)?

    init(config: StressTestConfig) {
        self.config = config
        self.testStart = Date()
        self.results = StressTestResults(startedAt: Date())

        // Open log file
        let logURL = URL(fileURLWithPath: config.logPath)
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: config.logPath, contents: nil)
        self.logFile = try? FileHandle(forWritingTo: logURL)
    }

    // MARK: - Logging

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        print(line)
        logFile?.write((line + "\n").data(using: .utf8) ?? Data())
    }

    // MARK: - Connect

    func connect() async throws {
        let urlString = "wss://api.openai.com/v1/realtime?model=\(config.model)"
        guard let url = URL(string: urlString) else { throw Error.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        log("🔌 Connecting to \(urlString)")
        sessionStart = Date()

        let session = URLSession(configuration: .ephemeral)
        let ws = session.webSocketTask(with: request)
        self.webSocket = ws
        ws.resume()

        try await Task.sleep(for: .milliseconds(500))

        isConnected = true
        results.totalSessions += 1
        log("✅ Connected (session #\(results.totalSessions))")

        // Configure for dictation (text-only modality)
        try send("""
        {
            "type": "session.update",
            "session": {
                "modalities": ["text"],
                "instructions": "Transcribe exactly what was said. Output only the spoken words.",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": {
                    "model": "gpt-4o-mini-transcribe",
                    "language": "\(config.language)"
                },
                "turn_detection": null,
                "max_response_output_tokens": 1024
            }
        }
        """)

        startReceiving()
    }

    func disconnect() {
        isConnected = false
        if let start = sessionStart {
            let duration = Date().timeIntervalSince(start)
            results.sessionDurations.append(duration)
            log("🔌 Disconnected after \(String(format: "%.1f", duration))s")
        }
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil

        if let start = sessionStart {
            results.sessionDurations.append(Date().timeIntervalSince(start))
        }
    }

    // MARK: - Stream Audio

    /// Stream a single utterance: send audio chunks in real-time, then commit.
    func streamUtterance(audioChunks: [Data]) async throws {
        guard isConnected else { throw Error.notConnected }

        let chunkInterval: UInt64 = 20_000_000 // 20ms in nanoseconds (real-time pacing)
        var chunksSent = 0

        log("🎙️ Streaming \(audioChunks.count) chunks (\(String(format: "%.1f", Double(audioChunks.count) * 20.0 / 1000.0))s of audio)")

        for chunk in audioChunks {
            let base64 = chunk.base64EncodedString()
            try send("""
            {"type":"input_audio_buffer.append","audio":"\(base64)"}
            """)
            chunksSent += 1

            // Real-time pacing (20ms per chunk)
            try await Task.sleep(nanoseconds: chunkInterval)
        }

        results.totalAudioSeconds += Double(chunksSent) * 20.0 / 1000.0

        // Commit and request response
        try send("""
        {"type":"input_audio_buffer.commit"}
        """)
        try send("""
        {"type":"response.create","response":{"modalities":["text"]}}
        """)

        log("📤 Committed \(chunksSent) chunks, waiting for response...")
    }

    // MARK: - Main Test Loop

    func runStressTest() async -> StressTestResults {
        log("🧪 === STRESS TEST STARTED ===")
        log("📊 Model: \(config.model)")
        log("📊 Utterance duration: \(config.utteranceDurationSeconds)s")
        log("📊 Gap between utterances: \(config.interUtteranceGap)s")
        log("📊 Tone bursts: \(config.useToneBursts)")
        log("📊 Max duration: \(config.maxDurationSeconds > 0 ? "\(config.maxDurationSeconds)s" : "unlimited")")
        log("")

        // Pre-generate audio
        let audioData = AudioGenerator.generatePCM16(
            durationSeconds: config.utteranceDurationSeconds,
            mode: config.useToneBursts
        )
        let chunks = AudioGenerator.chunkAudio(audioData)
        log("🎵 Generated \(chunks.count) audio chunks (\(String(format: "%.1f", config.utteranceDurationSeconds))s)")

        var sessionIndex = 0
        let deadline = config.maxDurationSeconds > 0
            ? Date().addingTimeInterval(config.maxDurationSeconds)
            : Date.distantFuture

        while Date() < deadline {
            sessionIndex += 1
            log("")
            log("━━━ Session #\(sessionIndex) ━━━")

            // Connect
            do {
                try await connect()
            } catch {
                log("❌ Connection failed: \(error)")
                results.errors.append("Session \(sessionIndex) connect failed: \(error)")
                results.hardLimitHit = true
                results.hardLimitMessage = "Connection refused: \(error.localizedDescription)"
                if results.firstErrorAfterSession == nil {
                    results.firstErrorAfterSession = sessionIndex
                }
                break
            }

            // Brief settle
            try? await Task.sleep(for: .milliseconds(500))

            // Stream utterance
            do {
                try await streamUtterance(audioChunks: chunks)
            } catch {
                log("❌ Stream failed: \(error)")
                results.errors.append("Session \(sessionIndex) stream failed: \(error)")
                results.hardLimitHit = true
                results.hardLimitMessage = "Stream error: \(error.localizedDescription)"
                if results.firstErrorAfterSession == nil {
                    results.firstErrorAfterSession = sessionIndex
                }
                disconnect()
                break
            }

            // Wait for response (max 10s)
            log("⏳ Waiting for response...")
            try? await Task.sleep(for: .seconds(10))

            // Check if still connected
            if !isConnected {
                log("⚠️ Disconnected unexpectedly after session \(sessionIndex)")
                results.wsDisconnectCount += 1
                if results.firstErrorAfterSession == nil {
                    results.firstErrorAfterSession = sessionIndex
                }
                // Try reconnecting
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            // Disconnect this session
            disconnect()

            // Inter-utterance gap
            if Date() < deadline {
                log("💤 Waiting \(config.interUtteranceGap)s before next session...")
                try? await Task.sleep(for: .seconds(config.interUtteranceGap))
            }
        }

        results.endedAt = Date()
        log("")
        log(results.summary)

        // Save results JSON
        saveResults()

        // Close log
        logFile?.closeFile()

        return results
    }

    // MARK: - Receiving

    private func startReceiving() {
        guard let ws = webSocket, isConnected else { return }

        ws.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.isConnected else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let json): self.handleEvent(json)
                    case .data(let d):
                        if let s = String(data: d, encoding: .utf8) { self.handleEvent(s) }
                    @unknown default: break
                    }
                    self.startReceiving()

                case .failure(let err):
                    if self.isConnected {
                        self.log("⚠️ WebSocket error: \(err)")
                        self.onError?(err.localizedDescription)
                        self.isConnected = false
                        self.results.wsDisconnectCount += 1
                    }
                }
            }
        }
    }

    private func handleEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "session.created":
            log("  ✅ Session created")

        case "session.updated":
            log("  ✅ Session configured")

        case "rate_limits.updated":
            // This is the goldmine — parse everything
            let remaining = obj["remaining"] as? [String: Any] ?? [:]
            let total = obj["total"] as? [String: Any] ?? [:]
            let reset = obj["reset"] as? [String: Any] ?? [:]

            let snapshot = RateLimitSnapshot(
                timestamp: Date(),
                sessionIndex: results.totalSessions,
                remainingRequests: remaining["requests"] as? Int,
                remainingTokens: remaining["tokens"] as? Int,
                totalRequests: total["requests"] as? Int,
                totalTokens: total["tokens"] as? Int,
                resetRequestsMs: (reset["requests"] as? Double),
                resetTokensMs: (reset["tokens"] as? Double),
                rawJSON: json
            )

            results.rateLimitSnapshots.append(snapshot)

            // Update totals
            if let t = snapshot.totalTokens { results.totalTokensConsumed = max(results.totalTokensConsumed, t) }
            if let t = snapshot.totalRequests { results.totalRequestsUsed = max(results.totalRequestsUsed, t) }

            // Calculate peaks
            calculatePeaks()

            log("  📊 Rate Limits: remaining=\(remaining), total=\(total), reset=\(reset)")

            onRateLimit?(snapshot)

        case "conversation.item.input_audio_transcription.completed":
            if let t = obj["transcript"] as? String {
                log("  📝 Transcript: \"\(t.prefix(100))\"")
                onTranscript?(t)
            }

        case "response.done":
            log("  ✅ Response complete")
            onSessionComplete?()

        case "error":
            let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? json
            log("  ❌ Error: \(msg)")
            results.errors.append("Session \(results.totalSessions): \(msg)")

            // Check for rate limit errors
            if msg.lowercased().contains("rate limit") || msg.lowercased().contains("quota") {
                results.hardLimitHit = true
                results.hardLimitMessage = msg
                if results.firstErrorAfterSession == nil {
                    results.firstErrorAfterSession = results.totalSessions
                }
            }

            onError?(msg)

        default:
            // Only log non-trivial events
            if !type.hasPrefix("session.") && type != "input_audio_buffer.committed" && type != "conversation.item.created" {
                log("  📨 \(type)")
            }
        }
    }

    private func calculatePeaks() {
        guard results.rateLimitSnapshots.count >= 2 else { return }

        // Look at 60-second windows
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        let recent = results.rateLimitSnapshots.filter { $0.timestamp > oneMinuteAgo }

        if recent.count >= 2 {
            let firstTotal = recent.first?.totalTokens ?? 0
            let lastTotal = recent.last?.totalTokens ?? 0
            let consumed = (lastTotal ?? 0) - (firstTotal ?? 0)
            if consumed > results.peakTokensPerMinute {
                results.peakTokensPerMinute = consumed
            }

            let firstReq = recent.first?.totalRequests ?? 0
            let lastReq = recent.last?.totalRequests ?? 0
            let reqConsumed = (lastReq ?? 0) - (firstReq ?? 0)
            if reqConsumed > results.peakRequestsPerMinute {
                results.peakRequestsPerMinute = reqConsumed
            }
        }
    }

    // MARK: - Helpers

    private func send(_ message: String) throws {
        guard let ws = webSocket else { throw Error.notConnected }
        ws.send(.string(message)) { error in
            if let error { print("⚠️ Send error: \(error)") }
        }
    }

    private func saveResults() {
        let resultsURL = URL(fileURLWithPath: config.resultsPath)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(results) {
            try? data.write(to: resultsURL)
            log("💾 Results saved to \(resultsURL.path)")
        }
    }

    enum Error: LocalizedError {
        case invalidURL
        case notConnected
        case authFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .notConnected: return "Not connected"
            case .authFailed: return "Auth failed"
            }
        }
    }
}

// MARK: - Tests

@Suite("Realtime API Stress Test")
struct RealtimeStressTest {

    @Test("Run stress test with 60s duration")
    @MainActor
    func testSixtySecondBlast() async throws {
        // Get token from keychain (must be signed in via Flow app)
        let token = try getAccessToken()

        var config = StressTestConfig.fromEnv(token: token)
        if config.maxDurationSeconds == 0 { config.maxDurationSeconds = 60 }

        let client = StressTestClient(config: config)
        let results = await client.runStressTest()

        // Assertions
        #expect(results.totalSessions >= 1, "Should complete at least 1 session")
        #expect(results.rateLimitSnapshots.count >= 1, "Should capture rate limit data")
        #expect(results.errors.count == 0 || results.hardLimitHit, "Errors should indicate rate limit hit")

        print(results.summary)
    }

    @Test("Run stress test until failure (unlimited)")
    @MainActor
    func testUntilFailure() async throws {
        let token = try getAccessToken()
        let env = ProcessInfo.processInfo.environment
        let parallel = max(1, Int(env["FLOW_STRESS_PARALLEL"] ?? "1") ?? 1)

        print("🚀 Spawning \(parallel) concurrent worker(s)")

        await withTaskGroup(of: (Int, StressTestResults).self) { group in
            for i in 1...parallel {
                group.addTask { @MainActor in
                    var cfg = StressTestConfig.fromEnv(token: token)
                    // Override worker index when parallel > 1 so each writes a unique file
                    if parallel > 1 { cfg.workerIndex = i }
                    let client = StressTestClient(config: cfg)
                    let results = await client.runStressTest()
                    return (i, results)
                }
            }

            for await (workerIdx, results) in group {
                print("\n━━━ Worker #\(workerIdx) summary ━━━")
                print(results.summary)
                print("📊 Rate Limit Progression (worker #\(workerIdx)):")
                for (i, snap) in results.rateLimitSnapshots.enumerated() {
                    print("  [\(i)] remaining_tokens=\(snap.remainingTokens ?? -1) total_tokens=\(snap.totalTokens ?? -1) remaining_requests=\(snap.remainingRequests ?? -1)")
                }
            }
        }
    }

    // MARK: - Token Retrieval

    private func getAccessToken() throws -> String {
        // Try to load from Keychain via the same KeychainStore Flow uses
        // The keychain items are saved when you sign in through the Flow app

        // Method 1: Try keychain directly
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.flow.auth",
            kSecAttrAccount as String: "tokens",
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["access_token"] as? String {
            return token
        }

        // Method 2: Try environment variable
        if let token = ProcessInfo.processInfo.environment["OPENAI_TOKEN"], !token.isEmpty {
            return token
        }

        // Method 3: Try file
        let tokenFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flow/test-token").path
        if let token = try? String(contentsOfFile: tokenFile).trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }

        throw TestError.noToken
    }

    enum TestError: Error, LocalizedError {
        case noToken

        var errorDescription: String? {
            switch self {
            case .noToken:
                return """
                No access token found. Sign in through the Flow app first, or:
                1. Set OPENAI_TOKEN env var: export OPENAI_TOKEN=your_token
                2. Or save to ~/.flow/test-token
                """
            }
        }
    }
}

// MARK: - Standalone Runner (legacy — kept for reference; @main removed because it
// collides with the test runner's auto-generated main symbol when this file lives
// inside a testTarget. To run: use `swift test --filter RealtimeStressTest/testUntilFailure`.)

struct StressTestRunner {
    static func main() async {
        print("🧪 ChatFlow Realtime API Stress Test")
        print("=====================================\n")

        // Get token
        guard let token = getToken() else {
            print("❌ No token found. Options:")
            print("   1. Sign in through Flow app (stores in Keychain)")
            print("   2. export OPENAI_TOKEN=your_token")
            print("   3. echo 'your_token' > ~/.flow/test-token")
            Foundation.exit(1)
        }

        let config = StressTestConfig.fromEnv(token: token)

        print("📝 Log file: \(config.logPath)")
        print("🏷️  Tier: \(config.tier.isEmpty ? "(untagged)" : config.tier), worker: \(config.workerIndex)")
        print("🔥 Aggressive: utterance=\(config.utteranceDurationSeconds)s gap=\(config.interUtteranceGap)s")
        if config.maxDurationSeconds > 0 {
            print("⏱️  Running for \(Int(config.maxDurationSeconds))s...\n")
        } else {
            print("⏱️  Running until failure (Ctrl+C to stop)...\n")
        }

        let client = StressTestClient(config: config)
        let results = await client.runStressTest()

        print(results.summary)

        // Save tier-tagged results
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let resultsURL = URL(fileURLWithPath: config.resultsPath)
        if let data = try? encoder.encode(results) {
            try? data.write(to: resultsURL)
            print("💾 Full results saved to \(resultsURL.path)")
        }
    }

    static func getToken() -> String? {
        // Env var
        if let token = ProcessInfo.processInfo.environment["OPENAI_TOKEN"], !token.isEmpty {
            return token
        }
        // File
        let tokenFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".flow/test-token").path
        if let token = try? String(contentsOfFile: tokenFile).trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }
        // Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.flow.auth",
            kSecAttrAccount as String: "tokens",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["access_token"] as? String {
            return token
        }
        return nil
    }
}
