import Foundation
import CoreGraphics
import ImageIO
import AppKit

/// Captures a screenshot for enhanced dictation context.
///
/// When the user triggers "enhanced dictation" (Ctrl+Shift+Space instead of Ctrl+Space):
/// 1. Capture the active display (~2ms)
/// 2. Downscale to 1280px wide for fast upload
/// 3. Return the base64 PNG + dimensions to the caller
///
/// The caller (DictationEngine) sends the image directly through the Realtime API
/// WebSocket as an `input_image` content item. The model sees the screenshot
/// alongside the audio and uses it for better transcription accuracy.
///
/// No separate vision API call needed — the Realtime model handles vision natively.
final class ScreenContextExtractor {
    static let shared = ScreenContextExtractor()

    private let maxImageWidth: CGFloat = 1280

    struct Screenshot {
        let base64PNG: String
        let width: Int
        let height: Int
        let byteCount: Int
    }

    private init() {}

    // MARK: - Public API

    /// Capture the active display and return a base64-encoded PNG screenshot.
    /// Returns nil if capture or encoding fails (graceful degradation).
    func captureScreenshot() -> Screenshot? {
        guard let image = captureActiveDisplay() else {
            print("📸 Screen capture failed — skipping enhanced context")
            return nil
        }

        guard let screenshot = downscaleAndEncode(image) else {
            print("📸 Image encoding failed — skipping enhanced context")
            return nil
        }

        print("📸 Screenshot captured (\(image.width)x\(image.height) → \(screenshot.width)x\(screenshot.height), \(screenshot.byteCount) bytes)")
        return screenshot
    }

    // MARK: - Screen Capture

    /// Capture the display that currently has the mouse cursor.
    private func captureActiveDisplay() -> CGImage? {
        guard let screen = NSScreen.screenWithMouse ?? NSScreen.main else {
            print("📸 No screen found (screenWithMouse=nil, main=nil)")
            return nil
        }

        // Get the CGDirectDisplayID from the screen's device description
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else {
            print("📸 No display ID found in screen device description")
            return nil
        }

        // Capture the full screen
        let rect = screen.frame
        let image = CGDisplayCreateImage(displayID, rect: rect)

        if image == nil {
            print("📸 CGDisplayCreateImage returned nil — screen recording permission required")
            print("📸   displayID=\(displayID), rect=\(rect)")
            // Open System Settings > Screen Recording so user can grant permission
            // CGPreflightScreenCaptureAccess/CGRequestScreenCaptureAccess don't reliably open settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
                print("📸 Opened System Settings > Screen Recording")
            }
        }

        return image
    }

    // MARK: - Image Processing

    /// Downscale the image and convert to base64 PNG.
    private func downscaleAndEncode(_ image: CGImage) -> Screenshot? {
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
        let base64 = pngData.base64EncodedString()

        return Screenshot(
            base64PNG: base64,
            width: newWidth,
            height: newHeight,
            byteCount: pngData.count
        )
    }
}
