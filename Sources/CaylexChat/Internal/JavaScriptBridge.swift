#if os(iOS)
import AVFoundation
import Foundation
import UIKit
import WebKit

@MainActor
final class JavaScriptBridge: NSObject, ChatCommandBridge, WKNavigationDelegate, WKUIDelegate,
                              WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    private weak var webView: WKWebView?
    private let controller: CaylexChatController
    private var configuration: CaylexChatConfiguration
    private var server: (any WidgetResourceServing)?
    private let makeServer: (URL) -> any WidgetResourceServing
    private var resourceURL: URL?
    private var loaded = false
    private var stopped = false
    private var clearStorageOnLoad = false
    private var refreshGeneration = 0
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<String, Error>?
    private var bootTimeout: Task<Void, Never>?
    private lazy var transport = NativeHTTPTransport(baseURL: configuration.apiBaseURL) { [weak self] event in
        self?.webView?.callAsyncJavaScript("window.CaylexHTTP.receive(event)", arguments: ["event": event], in: nil, in: .page, completionHandler: nil)
    }

    init(configuration: CaylexChatConfiguration, controller: CaylexChatController,
         makeServer: @escaping (URL) -> any WidgetResourceServing = { WidgetResourceServer(root: $0) }) {
        self.configuration = configuration
        self.controller = controller
        self.makeServer = makeServer
    }

    func start(_ webView: WKWebView) {
        guard !stopped, server == nil else { return }
        self.webView = webView
        guard controller.attach(self) else { return }
        do {
            try configuration.validate()
            guard let root = Bundle.module.resourceURL,
                  FileManager.default.fileExists(atPath: root.appendingPathComponent("chat-widget.js").path),
                  FileManager.default.fileExists(atPath: root.appendingPathComponent("native-fetch.js").path) else {
                throw CaylexChatError.missingResources
            }
            let server = makeServer(root)
            self.server = server
            server.start { [weak self, weak server] result in
                Task { @MainActor in
                    guard let self, !self.stopped, let server, self.server === server else { return }
                    switch result {
                    case .success(let url): self.resourceURL = url; self.reload()
                    case .failure(let error):
                        server.stop()
                        self.server = nil
                        self.resourceURL = nil
                        self.controller.failed(error)
                    }
                }
            }
            if observers.isEmpty { observeLifecycle() }
        } catch { controller.failed(error) }
    }

    func update(_ config: CaylexChatConfiguration) {
        guard configuration != config else { return }
        do { try config.validate() } catch { controller.report(error); return }
        let identityChanged = configuration.apiBaseURL != config.apiBaseURL ||
            configuration.agentInstanceId != config.agentInstanceId || configuration.tenantUserId != config.tenantUserId
        if configuration.presentation != config.presentation || configuration.enableCompactMode != config.enableCompactMode {
            controller.expanded(config.presentation != .compact || !config.enableCompactMode)
        }
        configuration = config
        transport.update(baseURL: config.apiBaseURL)
        if server == nil, let webView { start(webView); return }
        if identityChanged {
            clearStorageOnLoad = true
            refreshGeneration += 1
            refreshTask?.cancel(); refreshTask = nil
            reload()
        }
        else if loaded { configure() }
    }

    func reload() {
        guard !stopped, let webView else { return }
        guard let url = resourceURL else {
            if server == nil { start(webView) }
            return
        }
        loaded = false
        transport.cancelRequests()
        controller.loading()
        controller.expanded(configuration.presentation != .compact || !configuration.enableCompactMode)
        bootTimeout?.cancel()
        bootTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard let self, self.controller.status == .loading else { return }
            self.controller.failed(CaylexChatError.bridge("The chat widget did not finish loading"))
        }
        webView.load(URLRequest(url: url))
    }

    private func configure() {
        guard let webView else { return }
        do {
            let data = try JSONEncoder().encode(configuration)
            let config = try JSONSerialization.jsonObject(with: data)
            let clearStorage = clearStorageOnLoad
            clearStorageOnLoad = false
            webView.callAsyncJavaScript("if (clearStorage) { sessionStorage.clear(); localStorage.clear(); } window.CaylexHTTP.configure(config.apiBaseUrl); window.CaylexNative.configure(config)",
                arguments: ["config": config, "clearStorage": clearStorage], in: nil, in: .page) { [weak self] result in
                    if case .failure(let error) = result { self?.controller.failed(error) }
                }
        } catch { controller.failed(error) }
    }

    func command(_ name: String, argument: String?) async throws {
        guard loaded, !stopped, let webView else { throw CaylexChatError.notReady }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.callAsyncJavaScript(
                "await window.CaylexNative.command(name, argument); return null",
                arguments: ["name": name, "argument": argument.map { $0 as Any } ?? NSNull()], in: nil, in: .page) { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
        }
    }

    func stop() {
        stopped = true
        bootTimeout?.cancel()
        refreshTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        transport.stop()
        server?.stop(); server = nil
        controller.detach(self)
    }

    private func observeLifecycle() {
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.loaded else { return }
                    self.webView?.callAsyncJavaScript("window.CaylexNative.command('suspend')", arguments: [:], in: nil, in: .page, completionHandler: nil)
                }
            })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.loaded else { return }
                    self.webView?.callAsyncJavaScript("window.CaylexNative.command('refresh'); document.dispatchEvent(new Event('visibilitychange'))", arguments: [:], in: nil, in: .page, completionHandler: nil)
                }
            })
    }

    private func trusted(_ message: WKScriptMessage) -> Bool {
        guard message.frameInfo.isMainFrame, let source = message.frameInfo.request.url, let resourceURL else { return false }
        return source.scheme == resourceURL.scheme && source.host == resourceURL.host && source.port == resourceURL.port && source.path == resourceURL.path
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard trusted(message), let body = message.body as? [String: Any] else { return }
        transport.receive(body)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard trusted(message), let body = message.body as? [String: Any], body["version"] as? Int == 1,
              let event = body["event"] as? String else { replyHandler(nil, "Invalid bridge message"); return }
        let payload = body["payload"] as? [String: Any] ?? [:]
        if event == "refreshToken" {
            guard let refresh = controller.refreshToken else { replyHandler(nil, "No token refresh handler configured"); return }
            if refreshTask == nil {
                refreshGeneration += 1
                refreshTask = Task { try await refresh() }
            }
            let generation = refreshGeneration
            let task = refreshTask!
            Task {
                do {
                    let token = try await task.value
                    guard !stopped, refreshGeneration == generation, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw CaylexChatError.bridge("Token refresh did not return a valid token")
                    }
                    replyHandler(token, nil)
                } catch { replyHandler(nil, error.localizedDescription) }
                if refreshGeneration == generation { refreshTask = nil }
            }
            return
        }
        switch event {
        case "ready": bootTimeout?.cancel(); controller.ready(payload)
        case "error": controller.report(CaylexChatError.bridge(payload["message"] as? String ?? "Chat error"))
        case "sessionCreated": if let id = payload["sessionId"] as? String { controller.sessionCreated(id) }
        case "sessionChanged":
            if let id = payload["sessionId"] as? String,
               let kind = CaylexChatSession.Kind(rawValue: payload["sessionType"] as? String ?? "chat") {
                controller.sessionChanged(CaylexChatSession(id: id, kind: kind))
            }
        case "expandedChanged": if let expanded = payload["expanded"] as? Bool { controller.expanded(expanded) }
        case "navigate":
            if let raw = payload["url"] as? String, let url = URL(string: raw), ["https", "http"].contains(url.scheme ?? "") {
                controller.onNavigate?(url, payload["pageName"] as? String ?? "")
            }
        default: replyHandler(nil, "Unknown bridge event"); return
        }
        replyHandler(NSNull(), nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; configure() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        controller.failed(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { controller.failed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { reload() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url == resourceURL { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if ["https", "http", "mailto", "tel"].contains(url.scheme ?? "") { open(url) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http", "mailto", "tel"].contains(url.scheme ?? "") { open(url) }
        return nil
    }
    private func open(_ url: URL) {
        if let handler = controller.onOpenURL { handler(url) } else { UIApplication.shared.open(url) }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        guard type == .microphone, frame.isMainFrame, let resourceURL,
              origin.host == resourceURL.host, origin.port == resourceURL.port,
              Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            decisionHandler(.deny); return
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { decisionHandler(granted ? .grant : .deny) }
        }
    }
}
#endif
