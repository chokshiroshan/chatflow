import XCTest
@testable import Flow

// Note: Many Flow types use macOS-specific frameworks.
// Tests here cover the portable logic.

final class ConfigTests: XCTestCase {

    func testDefaultConfig() {
        let config = FlowConfig()
        XCTAssertEqual(config.hotkey, "fn")
        XCTAssertEqual(config.hotkeyMode, .hold)
        XCTAssertEqual(config.language, "en")
        XCTAssertEqual(config.preferredMode, .dictation)
        XCTAssertEqual(config.realtimeModel, "gpt-realtime-1.5")
        XCTAssertEqual(config.voiceChatVoice, "alloy")
    }

    func testConfigSaveAndLoad() throws {
        let config = FlowConfig()
        config.save()
        let loaded = FlowConfig.load()
        XCTAssertEqual(loaded.hotkey, config.hotkey)
        XCTAssertEqual(loaded.hotkeyMode, config.hotkeyMode)
        XCTAssertEqual(loaded.language, config.language)
    }

    func testHotkeyKeyCodes() {
        XCTAssertEqual(HotkeyManager.keyCode(for: "fn"), 63)
        XCTAssertEqual(HotkeyManager.keyCode(for: "rightcmd"), 54)
        XCTAssertEqual(HotkeyManager.keyCode(for: "rightopt"), 62)
        XCTAssertEqual(HotkeyManager.keyCode(for: "f5"), 96)
        XCTAssertEqual(HotkeyManager.keyCode(for: "unknown"), 63) // defaults to fn
    }
}

final class StateTests: XCTestCase {

    func testFlowStateIcons() {
        XCTAssertEqual(FlowState.idle.icon, "🎤")
        XCTAssertEqual(FlowState.recording.icon, "🔴")
        XCTAssertEqual(FlowState.processing.icon, "⏳")
        XCTAssertEqual(FlowState.injecting.icon, "📝")
        XCTAssertEqual(FlowState.speaking.icon, "🔊")
        XCTAssertEqual(FlowState.error("test").icon, "❌")
    }

    func testFlowStateProperties() {
        XCTAssertTrue(FlowState.recording.isRecording)
        XCTAssertFalse(FlowState.idle.isRecording)
        XCTAssertFalse(FlowState.recording.isError)
        XCTAssertTrue(FlowState.error("x").isError)
        XCTAssertTrue(FlowState.recording.isActive)
        XCTAssertFalse(FlowState.idle.isActive)
    }
}

final class AudioFormatTests: XCTestCase {

    func testTargetSampleRate() {
        XCTAssertEqual(AudioCapture.targetSampleRate, 24000.0)
    }
}

final class WAVEncodingTests: XCTestCase {

    func testPCM16ToWAV() {
        // Create 100 samples of silence (PCM16)
        var pcmData = Data()
        for _ in 0..<100 {
            var sample: Int16 = 0
            pcmData.append(Data(bytes: &sample, count: 2))
        }

        let wav = GroqWhisperClient.pcm16ToWav(pcmData, sampleRate: 24000, channels: 1)

        // Check RIFF header
        XCTAssertEqual(wav[0], 0x52) // R
        XCTAssertEqual(wav[1], 0x49) // I
        XCTAssertEqual(wav[2], 0x46) // F
        XCTAssertEqual(wav[3], 0x46) // F

        // Check WAVE
        XCTAssertEqual(wav[8], 0x57)  // W
        XCTAssertEqual(wav[9], 0x41)  // A
        XCTAssertEqual(wav[10], 0x56) // V
        XCTAssertEqual(wav[11], 0x45) // E

        // Data size = 100 samples * 2 bytes = 200
        // File size = 200 + 36 = 236
        let fileSize = wav[4...7].withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self).littleEndian
        }
        XCTAssertEqual(Int(fileSize), 236)

        // Total WAV = 44 header + 200 data = 244 bytes
        XCTAssertEqual(wav.count, 244)
    }

    func testWAVNonZeroAudio() {
        // Create a simple sine wave sample
        var pcmData = Data()
        for i in 0..<100 {
            let val = Int16(sin(Double(i) * 0.1) * 16000.0)
            var sample = val.littleEndian
            pcmData.append(Data(bytes: &sample, count: 2))
        }

        let wav = GroqWhisperClient.pcm16ToWav(pcmData, sampleRate: 24000, channels: 1)
        XCTAssertEqual(wav.count, 244)

        // First audio sample should be at offset 44
        let firstSample = wav[44...45].withUnsafeBytes { ptr in
            ptr.load(as: Int16.self).littleEndian
        }
        XCTAssertEqual(firstSample, 0) // sin(0) = 0
    }
}

final class JWTTests: XCTestCase {

    func testExtractEmailFromJWT() {
        // Create a fake JWT with email in payload
        let header = Data("{}".utf8).base64EncodedString()
        let payload = """
        {"email":"test@example.com","name":"Test"}
        """.data(using: .utf8)!.base64EncodedString()
        let signature = "fakesig"
        let jwt = "\(header).\(payload).\(signature)"

        let email = ChatGPTAuth.extractEmailFromJWT(jwt)
        XCTAssertEqual(email, "test@example.com")
    }

    func testExtractEmailFromInvalidJWT() {
        XCTAssertNil(ChatGPTAuth.extractEmailFromJWT("not.a.jwt"))
        XCTAssertNil(ChatGPTAuth.extractEmailFromJWT(""))
        XCTAssertNil(ChatGPTAuth.extractEmailFromJWT("a.b"))
    }
}

final class PKCETests: XCTestCase {

    func testSHA256Base64URL() {
        let input = "test-verifier-string"
        let output = ChatGPTAuth.sha256Base64URL(input)

        // Should be base64url encoded (no +, /, =)
        XCTAssertFalse(output.contains("+"))
        XCTAssertFalse(output.contains("/"))
        XCTAssertFalse(output.contains("="))
        XCTAssertFalse(output.isEmpty)

        // Same input should produce same output
        let output2 = ChatGPTAuth.sha256Base64URL(input)
        XCTAssertEqual(output, output2)
    }

    func testSHA256Deterministic() {
        // Known SHA256 of empty string
        let empty = ChatGPTAuth.sha256Base64URL("")
        XCTAssertFalse(empty.isEmpty)

        // Different inputs → different hashes
        let a = ChatGPTAuth.sha256Base64URL("a")
        let b = ChatGPTAuth.sha256Base64URL("b")
        XCTAssertNotEqual(a, b)
    }
}
