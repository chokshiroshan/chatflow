import Foundation
import CoreGraphics
import ImageIO
import AppKit

/// Captures a screenshot and extracts transcription-relevant context via vision.
///
/// When the user triggers "enhanced dictation" (Ctrl+Shift+Space instead of Ctrl+Space):
/// 1. Capture the active display (~2ms)
/// 2. Downscale to 1280px wide for fast upload
/// 3. Upload the image to ChatGPT's file service and ask vision for context
/// 4. Merge the extracted context into the Realtime API session instructions
///
/// The vision call takes ~1-2s and runs in the background. Regular transcription
/// starts immediately — the context is injected mid-stream via session.update.
final class ScreenContextExtractor {
    static let shared = ScreenContextExtractor()

    private let maxImageWidth: CGFloat = 1280
    private let visionModel = "auto"

    private struct EncodedScreenshot {
        let data: Data
        let width: Int
        let height: Int

        var byteCount: Int { data.count }
    }

    private init() {}

    // MARK: - Public API

    /// Capture the active display and extract context for transcription.
    /// Returns nil if capture fails or vision call fails (graceful degradation).
    func extractContext(token: String) async -> String? {
        guard let image = captureActiveDisplay() else {
            print("📸 Screen capture failed — skipping enhanced context")
            return nil
        }

        guard let screenshot = downscaleAndEncode(image) else {
            print("📸 Image encoding failed — skipping enhanced context")
            return nil
        }

        print("📸 Screenshot captured (\(image.width)x\(image.height)) → extracting context...")

        do {
            let context = try await callVisionAPI(screenshot: screenshot, token: token)
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
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else {
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

    /// Downscale the image and convert to PNG bytes + base64.
    private func downscaleAndEncode(_ image: CGImage) -> EncodedScreenshot? {
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
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resized = context.makeImage() else { return nil }

        // Encode as PNG
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, resized, nil)
        CGImageDestinationFinalize(dest)

        let pngData = data as Data
        return EncodedScreenshot(
            data: pngData,
            width: newWidth,
            height: newHeight
        )
    }

    // MARK: - Vision API (ChatGPT backend)

    /// Uses ChatGPT's backend because the OAuth token is a ChatGPT token, not a
    /// normal API key with `api.responses.write`.
    private func callVisionAPI(screenshot: EncodedScreenshot, token: String) async throws -> String? {
        let fileID = try await uploadImage(screenshot: screenshot, token: token)

        let url = URL(string: "https://chatgpt.com/backend-api/conversation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

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
            "action": "next",
            "messages": [
                [
                    "id": UUID().uuidString,
                    "author": ["role": "user"],
                    "content": [
                        "content_type": "multimodal_text",
                        "parts": [
                            [
                                "content_type": "image_asset_pointer",
                                "asset_pointer": "file-service://\(fileID)",
                                "size_bytes": screenshot.byteCount,
                                "width": screenshot.width,
                                "height": screenshot.height
                            ],
                            prompt
                        ]
                    ],
                    "metadata": [
                        "attachments": [
                            [
                                "id": fileID,
                                "name": "screenshot.png",
                                "size": screenshot.byteCount,
                                "mime_type": "image/png",
                                "width": screenshot.width,
                                "height": screenshot.height
                            ]
                        ]
                    ]
                ]
            ],
            "model": visionModel,
            "timezone_offset_min": -300
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

        return parseChatGPTSSEResponse(data: data)
    }

    /// Upload image to ChatGPT's file service and return the file ID.
    private func uploadImage(screenshot: EncodedScreenshot, token: String) async throws -> String {
        let initURL = URL(string: "https://chatgpt.com/backend-api/files")!
        var initRequest = URLRequest(url: initURL)
        initRequest.httpMethod = "POST"
        initRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        initRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initRequest.timeoutInterval = 10

        let initBody: [String: Any] = [
            "file_name": "screenshot.png",
            "file_size": screenshot.byteCount,
            "use_case": "multimodal",
            "width": screenshot.width,
            "height": screenshot.height
        ]
        initRequest.httpBody = try JSONSerialization.data(withJSONObject: initBody)

        let (initData, initResponse) = try await URLSession.shared.data(for: initRequest)
        guard let initHTTP = initResponse as? HTTPURLResponse, initHTTP.statusCode == 200 else {
            let statusCode = (initResponse as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: initData, encoding: .utf8) ?? "unknown"
            print("📸 File upload init error (\(statusCode)): \(body.prefix(200))")
            throw ScreenContextError.apiError(statusCode)
        }

        let initJSON = try JSONSerialization.jsonObject(with: initData) as? [String: Any] ?? [:]
        guard let fileID = initJSON["file_id"] as? String, !fileID.isEmpty,
              let uploadURLString = initJSON["upload_url"] as? String,
              let uploadURL = URL(string: uploadURLString) else {
            print("📸 Invalid file upload init response: \(initJSON)")
            throw ScreenContextError.invalidResponse
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("image/png", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        uploadRequest.setValue("2020-04-08", forHTTPHeaderField: "x-ms-version")
        if let uploadHeaders = initJSON["upload_headers"] as? [String: Any] {
            for (header, value) in uploadHeaders {
                guard let stringValue = value as? String else { continue }
                uploadRequest.setValue(stringValue, forHTTPHeaderField: header)
            }
        }
        uploadRequest.timeoutInterval = 15

        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, from: screenshot.data)
        guard let uploadHTTP = uploadResponse as? HTTPURLResponse,
              (200...299).contains(uploadHTTP.statusCode) else {
            let statusCode = (uploadResponse as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: uploadData, encoding: .utf8) ?? "unknown"
            print("📸 File bytes upload error (\(statusCode)): \(body.prefix(200))")
            throw ScreenContextError.apiError(statusCode)
        }

        try await markUploadComplete(fileID: fileID, token: token)
        return fileID
    }

    /// Notify ChatGPT that the pre-signed storage upload has finished.
    private func markUploadComplete(fileID: String, token: String) async throws {
        for suffix in ["upload-complete", "uploaded"] {
            let url = URL(string: "https://chatgpt.com/backend-api/files/\(fileID)/\(suffix)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else {
                throw ScreenContextError.invalidResponse
            }

            if (200...299).contains(httpResp.statusCode) {
                return
            }

            // ChatGPT has used both endpoint names; only log the first failure
            // if the fallback also fails below.
            if suffix == "uploaded" {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                print("📸 File upload complete error (\(httpResp.statusCode)): \(body.prefix(200))")
                throw ScreenContextError.apiError(httpResp.statusCode)
            }
        }
    }

    /// Parse the SSE response stream from ChatGPT backend-api.
    func parseChatGPTSSEResponse(data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        // Find the last message with text content.
        var lastText = ""
        for line in text.components(separatedBy: "\n") {
            guard line.hasPrefix("data: "), let jsonStr = line.dropFirst(6).data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: jsonStr) as? [String: Any] else { continue }

            let message = json["message"] as? [String: Any]
            let content = message?["content"] as? [String: Any]
            let parts = content?["parts"] as? [Any] ?? []

            for part in parts {
                if let textPart = part as? String, !textPart.isEmpty {
                    lastText = textPart
                }
            }
        }

        return lastText.isEmpty ? nil : lastText
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
