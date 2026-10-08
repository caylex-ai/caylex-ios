import CaylexChat
import SwiftUI

@main
struct ChatDemoApp: App {
    var body: some Scene { WindowGroup { DemoView() } }
}

@MainActor
struct DemoView: View {
    @State private var configuration: CaylexChatConfiguration?
    @State private var connectionError: String?
    @State private var useLocalTokenServer = false
    @State private var selectedLayout: DemoLayout?

    var body: some View {
        Group {
            if let configuration {
                NavigationStack {
                    List(DemoLayout.allCases) { layout in
                        Button { selectedLayout = layout } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(layout.title).font(.headline)
                                    Text(layout.detail).font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.vertical, 10)
                            } icon: { Image(systemName: layout.symbol) }
                        }
                        .accessibilityIdentifier("layout-\(layout.rawValue)")
                    }
                    .navigationTitle("Chat layouts")
                    .toolbar {
                        Menu("Appearance") {
                            Button("Light") { self.configuration?.theme = .light }
                            Button("Dark") { self.configuration?.theme = .dark }
                        }
                    }
                }
                .fullScreenCover(item: $selectedLayout) { layout in
                    EmbeddingDemoScreen(configuration: configuration, layout: layout, refreshToken: {
                        if useLocalTokenServer { return try await fetchLocalToken(path: "token").widgetToken }
                        return "demo-token"
                    })
                }
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
        // Fixtures are opt-in so backend failures never look like AI replies.
        if ProcessInfo.processInfo.arguments.contains("--fixture") {
            configuration = Self.fixtureConfiguration()
            selectLaunchLayout()
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
            selectLaunchLayout()
        } catch {
            connectionError = "Start the local token server with your credentials file, then retry. " + error.localizedDescription
        }
    }

    private func selectLaunchLayout() {
        let prefix = "--layout="
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) {
            selectedLayout = DemoLayout(rawValue: String(argument.dropFirst(prefix.count)))
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
