import XCTest
@testable import Flow

final class FlowTests: XCTestCase {
    func testDefaultConfigValues() {
        let config = FlowConfig()

        XCTAssertEqual(config.hotkey, "ctrl+space")
        XCTAssertEqual(config.hotkeyMode, .hold)
        XCTAssertEqual(config.language, "en")
        XCTAssertEqual(config.injectMethod, .clipboard)
    }

    func testAuthStateSignedInHelper() {
        XCTAssertTrue(AuthState.signedIn(email: "test@example.com", plan: "ChatGPT").isSignedIn)
        XCTAssertFalse(AuthState.signedOut.isSignedIn)
    }

    func testRightCommandShortcutAliasesParseToRightCommandKey() {
        let onboardingCombo = HotkeyManager.KeyCombo.parse("right+cmd")
        let canonicalCombo = HotkeyManager.KeyCombo.parse("rcmd")

        XCTAssertEqual(onboardingCombo.keyCode, 54)
        XCTAssertEqual(onboardingCombo.displayName, "Right ⌘")
        XCTAssertEqual(onboardingCombo, canonicalCombo)
    }

    func testChatGPTVisionTextParsing() throws {
        let response = """
        data: {"message":{"content":{"parts":["The screen shows Xcode editing ScreenContextExtractor.swift."]}}}
        data: {"message":{"content":{"parts":["The screen shows ChatFlow logs in Terminal."]}}}
        """

        let text = ScreenContextExtractor.shared.parseChatGPTSSEResponse(data: Data(response.utf8))

        XCTAssertEqual(text, "The screen shows ChatFlow logs in Terminal.")
    }

    func testChatGPTVisionParserIgnoresImageParts() throws {
        let response = """
        data: {"message":{"content":{"parts":[{"content_type":"image_asset_pointer","asset_pointer":"file-service://file-123"},"Visible app is Xcode."]}}}
        """

        let text = ScreenContextExtractor.shared.parseChatGPTSSEResponse(data: Data(response.utf8))

        XCTAssertEqual(text, "Visible app is Xcode.")
    }
}
