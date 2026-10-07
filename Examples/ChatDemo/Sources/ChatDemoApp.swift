import CaylexChat
import SwiftUI

@main
struct ChatDemoApp: App {
    var body: some Scene { WindowGroup { DemoView() } }
}

@MainActor
struct DemoView: View {
    @StateObject private var controller = CaylexChatController()
    @State private var configuration: CaylexChatConfiguration?
    @State private var connectionError: String?
    @State private var useLocalTokenServer = false

    var body: some View {
        Group {
            if let configuration {
                CaylexChatView(configuration: configuration, controller: controller)
            } else if let connectionError {
                VStack(spacing: 12) {
                    Text("Could not connect to Caylex").font(.headline)
                    Text(connectionError).multilineTextAlignment(.center)
                    Button("Retry") { Task { await connect() } }
                }.padding(24)
            } else {
                ProgressView("Connecting…")
            }
        }
        .task { if configuration == nil { await connect() } }
    }

    private func connect() async {
        connectionError = nil
        controller.refreshToken = {
            if useLocalTokenServer { return try await fetchLocalToken(path: "token").widgetToken }
            return "demo-token"
        }
        // Fixtures are opt-in so backend failures never look like AI replies.
        if ProcessInfo.processInfo.arguments.contains("--fixture") {
            configuration = Self.fixtureConfiguration()
            return
        }
        do {
            let live = try await fetchLocalToken(path: "config")
            guard let url = URL(string: live.apiBaseUrl) else {
                throw CaylexChatError.bridge("The token server returned an invalid API URL")
            }
            var config = CaylexChatConfiguration(apiBaseURL: url, widgetToken: live.widgetToken)
            config.userName = live.userName
            config.sampleQueries = ["What can you help me with?"]
            useLocalTokenServer = true
            configuration = config
        } catch {
            connectionError = "Start the local token server with your credentials file, then retry. " + error.localizedDescription
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
