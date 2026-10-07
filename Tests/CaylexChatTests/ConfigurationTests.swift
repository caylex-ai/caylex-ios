import Foundation
import XCTest
@testable import CaylexChat

final class ConfigurationTests: XCTestCase {
    private func config() -> CaylexChatConfiguration {
        CaylexChatConfiguration(apiBaseURL: URL(string: "https://api.caylex.ai/api/v1/assistants")!, widgetToken: "test-token")
    }

    private func json(_ config: CaylexChatConfiguration) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
    }

    func testInitialSessionPreservesThreeDistinctHostIntents() throws {
        var config = config()
        XCTAssertNil(try json(config)["initialSessionId"])
        config.initialSession = .new
        XCTAssertTrue(try json(config)["initialSessionId"] is NSNull)
        config.initialSession = .existing("saved-session")
        XCTAssertEqual(try json(config)["initialSessionId"] as? String, "saved-session")
    }

    func testNativeConfigMatchesWebKeysAndFillsContainer() throws {
        let payload = try json(config())
        XCTAssertEqual(payload["apiBaseUrl"] as? String, "https://api.caylex.ai/api/v1/assistants/")
        XCTAssertNil(payload["apiBaseURL"])
        XCTAssertEqual(payload["height"] as? String, "100%")
        XCTAssertEqual(payload["width"] as? String, "100%")
        XCTAssertEqual(payload["enableExternalSessionSync"] as? Bool, true)
    }

    func testRejectsInvalidCredentialsAndNonLocalCleartext() throws {
        var config = config()
        config.apiBaseURL = URL(string: "http://example.com/api/")!
        XCTAssertThrowsError(try config.validate())
        config.apiBaseURL = URL(string: "http://127.0.0.1:8765/api/")!
        XCTAssertNoThrow(try config.validate())
        config.widgetToken = "  "
        XCTAssertThrowsError(try config.validate())
    }

    func testRequiresNavigationBaseAndNonEmptySessionID() throws {
        var config = config()
        config.initialSession = .existing(" ")
        XCTAssertThrowsError(try config.validate())
        config.initialSession = .automatic
        config.navigablePages = [.init(name: "Report", urlTemplate: "/reports/{id}")]
        XCTAssertThrowsError(try config.validate())
        config.navigationBaseUrl = "https://example.com"
        XCTAssertNoThrow(try config.validate())
    }

    #if os(iOS)
    @MainActor
    func testNativeTransportRestrictsOriginAndAPIPath() {
        let transport = NativeHTTPTransport(baseURL: URL(string: "https://api.caylex.ai/api/v1/assistants/")!, emit: { _ in })
        XCTAssertTrue(transport.allows(URL(string: "https://api.caylex.ai/api/v1/assistants/chat/stream")!))
        XCTAssertFalse(transport.allows(URL(string: "https://evil.example/api/v1/assistants/chat/stream")!))
        XCTAssertFalse(transport.allows(URL(string: "https://api.caylex.ai/api/v1/assistants-other/init")!))
        XCTAssertFalse(transport.allows(URL(string: "https://api.caylex.ai/api/v1/assistants/../billing")!))
        XCTAssertFalse(transport.allows(URL(string: "https://api.caylex.ai/api/v1/assistants/%2e%2e/billing")!))
        XCTAssertTrue(transport.allows(URL(string: "https://api.caylex.ai:443/api/v1/assistants/init")!))
    }
    #endif
}
