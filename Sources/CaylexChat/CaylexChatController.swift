#if os(iOS)
import Combine
import Foundation

public struct CaylexChatSession: Equatable, Sendable {
    public enum Kind: String, Sendable { case chat, backgroundTask = "background_task" }
    public let id: String
    public let kind: Kind
}

@MainActor
protocol ChatCommandBridge: AnyObject {
    func command(_ name: String, argument: String?) async throws
    func reload()
}

/// Own one controller per chat view. Keep it alive to preserve the web view across SwiftUI updates.
@MainActor
public final class CaylexChatController: ObservableObject {
    public enum Status: Equatable { case idle, loading, ready, failed(String) }
    @Published public private(set) var status: Status = .idle
    @Published public private(set) var session: CaylexChatSession?
    @Published public private(set) var isExpanded = true
    @Published public private(set) var microphoneSupported = false
    @Published public private(set) var realtimeSupported = false

    public var refreshToken: (() async throws -> String)?
    public var onError: ((Error) -> Void)?
    public var onSessionCreated: ((String) -> Void)?
    public var onSessionChanged: ((CaylexChatSession) -> Void)?
    public var onNavigate: ((URL, String) -> Void)?
    /// Handle authentication and external links. Defaults to opening the system browser.
    public var onOpenURL: ((URL) -> Void)?
    private weak var bridge: ChatCommandBridge?

    public init() {}

    /// Switch sessions without recreating React or the web view. Suitable for notification taps.
    public func openSession(_ id: String) async throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaylexChatError.invalidConfiguration("Session ID cannot be empty")
        }
        try await perform("restoreSession", argument: id)
    }
    public func sendMessage(_ message: String) async throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaylexChatError.invalidConfiguration("Message cannot be empty")
        }
        try await perform("sendMessage", argument: message)
    }
    public func startNewChat() async throws { try await perform("startNewChat") }
    public func stopGeneration() async throws { try await perform("stopGeneration") }
    public func resume() async throws { try await perform("resume") }
    public func refresh() async throws { try await perform("refresh") }
    public func reload() { bridge?.reload() }

    private func perform(_ name: String, argument: String? = nil) async throws {
        let deadline = Date().addingTimeInterval(30)
        while status == .loading && Date() < deadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard status == .ready, let bridge else { throw CaylexChatError.notReady }
        try await bridge.command(name, argument: argument)
    }

    func attach(_ bridge: ChatCommandBridge) -> Bool {
        guard self.bridge == nil || self.bridge === bridge else {
            report(CaylexChatError.bridge("Use a separate controller for each mounted CaylexChatView"))
            return false
        }
        self.bridge = bridge
        status = .loading
        return true
    }
    func detach(_ bridge: ChatCommandBridge) {
        guard self.bridge === bridge else { return }
        self.bridge = nil
        status = .idle
    }
    func loading() { status = .loading }
    func failed(_ error: Error) { status = .failed(error.localizedDescription); report(error) }
    func report(_ error: Error) { onError?(error) }
    func ready(_ payload: [String: Any]) {
        microphoneSupported = payload["microphoneSupported"] as? Bool ?? false
        realtimeSupported = payload["realtimeSupported"] as? Bool ?? false
        status = .ready
    }
    func sessionCreated(_ id: String) { onSessionCreated?(id) }
    func sessionChanged(_ session: CaylexChatSession) {
        self.session = session
        onSessionChanged?(session)
    }
    func expanded(_ value: Bool) { isExpanded = value }
}
#endif
