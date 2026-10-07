import CaylexChat
import SwiftUI

@main
struct ChatDemoApp: App {
    var body: some Scene { WindowGroup { DemoView() } }
}

@MainActor
struct DemoView: View {
    @StateObject private var controller = CaylexChatController()
    @State private var configuration: CaylexChatConfiguration = {
        var config = CaylexChatConfiguration(apiBaseURL: URL(string: "http://127.0.0.1:8765/api/")!, widgetToken: "expired-demo-token")
        config.userName = "Alex"
        config.sampleQueries = ["Show me what you can do", "Try a tool approval", "Help me navigate"]
        config.darkPrimaryColor = "#5575DC"
        config.darkBackgroundColor = "#0D0F1C"
        config.navigablePages = [.init(name: "Reports", urlTemplate: "/reports")]
        config.navigationBaseUrl = "https://example.com"
        return config
    }()
    @State private var settings = false
    @State private var apiURL = "http://127.0.0.1:8765/api/"
    @State private var token = "demo-token"
    @State private var notice = ""
    @State private var useLocalTokenServer = false
    @State private var restoreID = "saved-demo"

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                CaylexChatView(configuration: configuration, controller: controller)
                HStack {
                    Text(controller.session.map { "Session: \($0.id)" } ?? "Connecting…")
                    Spacer()
                    Text(notice).lineLimit(1)
                }
                .font(.caption2).foregroundColor(.secondary).padding(8)
            }
            .navigationTitle("Caylex Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Settings") { settings = true }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Restore") { Task { await run { try await controller.openSession(restoreID) } } }
                    Button("New") { Task { await run { try await controller.startNewChat() } } }
                    Button {
                        configuration.theme = configuration.theme == .light ? .dark : .light
                    } label: { Image(systemName: "circle.lefthalf.filled") }
                    .accessibilityLabel("Toggle theme")
                }
            }
            .sheet(isPresented: $settings) {
                NavigationView {
                    Form {
                        Section(header: Text("Widget credentials")) {
                            TextField("Assistants API base URL", text: $apiURL)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            SecureField("Widget token", text: $token)
                            Text("Use the local demo server, or enter a token minted by your backend. No platform API keys belong here.")
                                .font(.caption)
                        }
                        Section(header: Text("Local development backend")) {
                            Button("Load live widget token from local server") {
                                Task {
                                    await run {
                                        let live = try await fetchLocalToken(path: "config")
                                        guard let url = URL(string: live.apiBaseUrl) else { throw CaylexChatError.bridge("Invalid API URL") }
                                        configuration.apiBaseURL = url
                                        configuration.widgetToken = live.widgetToken
                                        configuration.userName = live.userName
                                        configuration.sampleQueries = ["What can you help me with?"]
                                        configuration.navigablePages = []
                                        configuration.initialSession = .new
                                        apiURL = live.apiBaseUrl
                                        token = live.widgetToken
                                        restoreID = ""
                                        useLocalTokenServer = true
                                        settings = false
                                    }
                                }
                            }
                            Text("Start demo-server.py with --credentials-file to mint tokens on your Mac. The app receives only widget tokens.").font(.caption)
                        }
                        Section(header: Text("Session routing")) {
                            TextField("Session ID to restore", text: $restoreID)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        Section {
                            Button("Connect") {
                                guard let url = URL(string: apiURL) else { notice = "Invalid API URL"; return }
                                configuration.apiBaseURL = url
                                configuration.widgetToken = token
                                configuration.navigablePages = []
                                useLocalTokenServer = false
                                settings = false
                            }
                        }
                    }
                    .navigationTitle("Demo settings")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { settings = false } } }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            controller.refreshToken = {
                // The demo backend deliberately expires the initial token.
                // Replace this with a request to your own token-minting backend.
                if useLocalTokenServer { return try await fetchLocalToken(path: "token").widgetToken }
                guard configuration.apiBaseURL.host == "127.0.0.1" else {
                    throw CaylexChatError.bridge("Configure a real token refresh endpoint for your backend")
                }
                notice = "Token refreshed"
                return "demo-token"
            }
            controller.onError = { notice = $0.localizedDescription }
            controller.onNavigate = { _, page in notice = "Navigate: \(page)" }
            controller.onSessionChanged = { _ in notice = "Session loaded" }
        }
    }

    private struct LiveToken: Decodable {
        let apiBaseUrl: String
        let widgetToken: String
        let userName: String
    }

    private func fetchLocalToken(path: String) async throws -> LiveToken {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8765/demo/\(path)")!)
        request.setValue("1", forHTTPHeaderField: "X-Caylex-Demo")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CaylexChatError.bridge("The local server could not mint a live widget token")
        }
        return try JSONDecoder().decode(LiveToken.self, from: data)
    }

    private func run(_ action: () async throws -> Void) async {
        do { try await action() } catch { notice = error.localizedDescription }
    }
}
