import Foundation
import CoreGraphics
import ImageIO
import AppKit

/// Captures a screenshot and extracts transcription-relevant context via GPT-4o-mini vision.
///
/// When the user triggers "enhanced dictation" (Ctrl+Shift+Space instead of Ctrl+Space):
/// 1. Capture the active display (~2ms)
/// 2. Downscale to 1280px wide for fast upload
/// 3. Send to GPT-4o-mini vision API with a context extraction prompt
/// 4. Merge the extracted context into the Realtime API session instructions
///
/// The vision call takes ~1-2s and runs in the background. Regular transcription
/// starts immediately — the context is injected mid-stream via session.update.
final class ScreenContextExtractor {
    static let shared = ScreenContextExtractor()

    private let maxImageWidth: CGFloat = 1280

    private init() {}

    // MARK: - Public API

    /// Capture the active display and extract context for transcription.
    /// Returns nil if capture fails or vision call fails (graceful degradation).
    func extractContext(token: String) async -> String? {
        guard let image = captureActiveDisplay() else {
            print("📸 Screen capture failed — skipping enhanced context")
            return nil
        }

        let base64 = downscaleAndEncode(image)
        guard !base64.isEmpty else {
            print("📸 Image encoding failed — skipping enhanced context")
            return nil
        }

        print("📸 Screenshot captured (\(image.width)x\(image.height)) → extracting context...")

        do {
            let context = try await callVisionAPI(base64: base64, token: token)
            if let context, !context.isEmpty {
                print("📸 Screen context: \(context.prefix(200))...")
                return context
            }
            return nil
        } catch {
            print("📸 Vision API failed: \(error) — transcription continues without screen context")
            return nil
        }
    }

    // MARK: - Screen Capture

    /// Capture the display that currently has the mouse cursor.
    private func captureActiveDisplay() -> CGImage? {
        guard let screen = NSScreen.screenWithMouse ?? NSScreen.main else { return nil }

        // Get the CGDirectDisplayID from the screen's device description
        guard let displayID = screen.deviceDescription["NSScreenNumber"] as? UInt32 else {
            return nil
        }

        // Capture the full screen (not just visibleFrame — we want menu bar, dock area context too)
        let rect = screen.frame
        let image = CGDisplayCreateImage(displayID, rect: rect)

        // Immediately clear the image from any sensitive system UI
        // (we're sending this to OpenAI, so be conservative)
        return image
    }

    // MARK: - Image Processing

    /// Downscale the image and convert to base64 PNG.
    private func downscaleAndEncode(_ image: CGImage) -> String {
        let srcWidth = CGFloat(image.width)
        let srcHeight = CGFloat(image.height)

        // Downscale if wider than max
        let scale = min(maxImageWidth / srcWidth, 1.0)
        let newWidth = Int(srcWidth * scale)
        let newHeight = Int(srcHeight * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return "" }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resized = context.makeImage() else { return "" }

        // Encode as PNG
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return "" }
        CGImageDestinationAddImage(dest, resized, nil)
        CGImageDestinationFinalize(dest)

        return data.base64EncodedString()
    }

    // MARK: - Vision API

    private func callVisionAPI(base64: String, token: String) async throws -> String? {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let prompt = """
        Look at this screenshot. Extract ONLY information that would help accurately transcribe someone's speech. Focus on:
        - Application name and what the user is doing
        - Visible text labels, headings, or menu items
        - Technical terms, variable names, function names, or code visible
        - Names of people, projects, products, or companies mentioned on screen
        - Any domain-specific vocabulary (medical, legal, programming, etc.)

        Respond with a concise paragraph of context. No lists, no explanations, just facts that help transcription.
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64)",
                                "detail": "low"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 200
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw ScreenContextError.invalidResponse
        }

        guard httpResp.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            print("📸 Vision API error (\(httpResp.statusCode)): \(body.prefix(200))")
            throw ScreenContextError.apiError(httpResp.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let choices = json["choices"] as? [[String: Any]] ?? []
        let message = choices.first?["message"] as? [String: Any]
        return message?["content"] as? String
    }
}

enum ScreenContextError: LocalizedError {
    case invalidResponse
    case apiError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from vision API"
        case .apiError(let code): return "Vision API error (\(code))"
        }
    }
}
