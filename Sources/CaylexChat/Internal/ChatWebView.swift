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
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
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
#endif
