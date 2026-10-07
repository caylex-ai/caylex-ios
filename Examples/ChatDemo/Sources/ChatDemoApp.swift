import CaylexChat
import SwiftUI

@main
struct ChatDemoApp: App {
    var body: some Scene { WindowGroup { DemoView() } }
}

@MainActor
struct DemoView: View {
    @StateObject private var controller = CaylexChatController()
    @State private var configuration = fixtureConfiguration()
    @State private var configured = false
    @State private var useLocalTokenServer = false

    var body: some View {
        Group {
            if configured {
                CaylexChatView(configuration: configuration, controller: controller)
            } else {
                ProgressView("Connecting…")
            }
        }
        .task {
            guard !configured else { return }
            controller.refreshToken = {
                if useLocalTokenServer { return try await fetchLocalToken(path: "token").widgetToken }
                return "demo-token"
            }
            // The demo host adds no navigation or debug chrome around the widget.
            // Keep credentials on the Mac; request a fresh widget token at launch.
            if let live = try? await fetchLocalToken(path: "config"),
               let url = URL(string: live.apiBaseUrl) {
                configuration = CaylexChatConfiguration(apiBaseURL: url, widgetToken: live.widgetToken)
                configuration.userName = live.userName
                configuration.sampleQueries = ["What can you help me with?"]
                useLocalTokenServer = true
            }
            configured = true
        }
    }

    private static func fixtureConfiguration() -> CaylexChatConfiguration {
        var config = CaylexChatConfiguration(apiBaseURL: URL(string: "http://127.0.0.1:8765/api/")!, widgetToken: "expired-demo-token")
        config.userName = "Alex"
        config.sampleQueries = ["Show me what you can do", "Try a tool approval", "Help me navigate"]
        config.darkPrimaryColor = "#5575DC"
        config.darkBackgroundColor = "#0D0F1C"
        config.navigablePages = [.init(name: "Reports", urlTemplate: "/reports")]
        config.navigationBaseUrl = "https://example.com"
        return config
    }

    private struct LiveToken: Decodable {
        let apiBaseUrl: String
        let widgetToken: String
        let userName: String
    }

    private func fetchLocalToken(path: String) async throws -> LiveToken {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8765/demo/\(path)")!)
        request.timeoutInterval = 15
        request.setValue("1", forHTTPHeaderField: "X-Caylex-Demo")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CaylexChatError.bridge("The local server could not mint a live widget token")
        }
        return try JSONDecoder().decode(LiveToken.self, from: data)
    }
}
