#if os(iOS)
import Foundation
import WebKit
import XCTest
@testable import CaylexChat

final class BridgeRecoveryTests: XCTestCase {
    @MainActor
    func testDeferredDetachDoesNotResetRemountedController() async throws {
        let controller = CaylexChatController()
        let first = JavaScriptBridge(configuration: configuration(), controller: controller,
                                     makeServer: { _ in StubResourceServer(fails: false) })
        let second = JavaScriptBridge(configuration: configuration(), controller: controller,
                                      makeServer: { _ in StubResourceServer(fails: false) })
        let firstView = WKWebView()
        let secondView = WKWebView()
        first.start(firstView)
        first.stop()
        second.start(secondView)
        defer { second.stop() }
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(controller.status, .loading)
    }

    @MainActor
    func testDetachEventuallyReturnsControllerToIdle() async throws {
        let (bridge, controller, webView, _, _) = fixture()
        bridge.start(webView)
        bridge.stop()
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(controller.status, .idle)
    }

    @MainActor
    func testRetryStartsNewListenerAfterStartupFailure() async throws {
        let (bridge, controller, webView, failed, replacement) = fixture()
        defer { bridge.stop() }
        bridge.start(webView)
        try await waitForFailure(controller)
        XCTAssertEqual(failed.stopCount, 1)

        controller.reload() // The same path used by the displayed Retry button.
        XCTAssertEqual(replacement.startCount, 1)
        XCTAssertEqual(controller.status, .loading)
    }

    @MainActor
    func testConfigurationUpdateRecoversAfterStartupFailure() async throws {
        let (bridge, controller, webView, failed, replacement) = fixture()
        defer { bridge.stop() }
        bridge.start(webView)
        try await waitForFailure(controller)
        var config = configuration()
        config.widgetToken = "replacement-token"
        bridge.update(config)

        XCTAssertEqual(failed.stopCount, 1)
        XCTAssertEqual(replacement.startCount, 1)
        XCTAssertEqual(controller.status, .loading)
    }

    @MainActor
    private func configuration() -> CaylexChatConfiguration {
        CaylexChatConfiguration(apiBaseURL: URL(string: "https://api.caylex.ai/api/v1/assistants/")!, widgetToken: "test-token")
    }

    @MainActor
    private func fixture() -> (JavaScriptBridge, CaylexChatController, WKWebView, StubResourceServer, StubResourceServer) {
        let controller = CaylexChatController()
        let failed = StubResourceServer(fails: true)
        let replacement = StubResourceServer(fails: false)
        var attempts = 0
        let bridge = JavaScriptBridge(configuration: configuration(), controller: controller, makeServer: { _ in
            attempts += 1
            return attempts == 1 ? failed : replacement
        })
        return (bridge, controller, WKWebView(), failed, replacement)
    }

    @MainActor
    private func waitForFailure(_ controller: CaylexChatController) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if case .failed = controller.status { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Expected the simulated listener startup failure")
        throw NSError(domain: "BridgeRecoveryTests", code: 1)
    }
}

// The test invokes this stub only on the main actor; it creates no queue or listener.
private final class StubResourceServer: WidgetResourceServing, @unchecked Sendable {
    let fails: Bool
    private(set) var startCount = 0
    private(set) var stopCount = 0
    init(fails: Bool) { self.fails = fails }
    func start(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        startCount += 1
        if fails { completion(.failure(NSError(domain: "SimulatedListenerFailure", code: 1))) }
    }
    func stop() { stopCount += 1 }
}
#endif
