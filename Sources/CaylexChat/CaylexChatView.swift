#if os(iOS)
import SwiftUI

/// Embed inside your own navigation or sheet. The view follows its parent's size and keyboard safe area.
@MainActor
public struct CaylexChatView: View {
    public var configuration: CaylexChatConfiguration
    @ObservedObject private var controller: CaylexChatController

    public init(configuration: CaylexChatConfiguration, controller: CaylexChatController) {
        self.configuration = configuration
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            ChatWebView(configuration: configuration, controller: controller)
            if controller.status == .loading {
                ProgressView("Loading chat…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            if case .failed(let message) = controller.status {
                VStack(spacing: 12) {
                    Text("Chat could not load").font(.headline)
                    Text(message).font(.callout).multilineTextAlignment(.center)
                    Button("Retry") { controller.reload() }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
            }
        }
    }
}
#endif
