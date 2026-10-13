#if os(iOS)
import AVFoundation
import SwiftUI
import WebKit

@MainActor
struct ChatWebView: UIViewRepresentable {
    let configuration: CaylexChatConfiguration
    let controller: CaylexChatController

    func makeCoordinator() -> JavaScriptBridge { JavaScriptBridge(configuration: configuration, controller: controller) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "caylex")
        config.userContentController.add(context.coordinator, name: "caylexHTTP")
        if let url = Bundle.module.url(forResource: "native-fetch", withExtension: "js"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let webView = ChatViewportWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.start(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(configuration)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: JavaScriptBridge) {
        coordinator.stop()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }
}

@MainActor
private final class ChatViewportWebView: WKWebView {
    private var offsetObservation: NSKeyValueObservation?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.keepRootViewportInPlace()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        keepRootViewportInPlace()
    }

    private func keepRootViewportInPlace() {
        // SwiftUI owns keyboard avoidance by resizing this view. WebKit may still
        // scroll its root UIScrollView to reveal the focused textarea even when
        // isScrollEnabled is false. That second adjustment moves the entire chat
        // during the keyboard animation. Inner DOM message/drawer scrolling stays
        // independent; only the fixed outer viewport is pinned.
        guard scrollView.contentOffset != .zero else { return }
        scrollView.setContentOffset(.zero, animated: false)
    }
}
#endif
