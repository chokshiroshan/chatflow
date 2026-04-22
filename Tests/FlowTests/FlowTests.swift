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
}
