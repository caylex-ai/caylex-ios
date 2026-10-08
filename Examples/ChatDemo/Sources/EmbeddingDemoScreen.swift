import CaylexChat
import SwiftUI

enum DemoLayout: String, CaseIterable, Identifiable {
    case fullScreen = "full", bottomDock = "dock", framed = "framed"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fullScreen: "Full screen"
        case .bottomDock: "Bottom dock"
        case .framed: "Top bar & bottom dock"
        }
    }
    var detail: String {
        switch self {
        case .fullScreen: "Chat extends behind the status bar and home indicator."
        case .bottomDock: "Chat fills the space above a native app dock."
        case .framed: "A rounded chat card inside your app's top bar and dock."
        }
    }
    var symbol: String {
        switch self {
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        case .bottomDock: "rectangle.bottomthird.inset.filled"
        case .framed: "rectangle.inset.filled"
        }
    }
}

/// Host app layout belongs here; the package only fills the space it receives.
@MainActor
struct EmbeddingDemoScreen: View {
    let configuration: CaylexChatConfiguration
    let layout: DemoLayout
    @StateObject private var controller: CaylexChatController
    @Environment(\.dismiss) private var dismiss

    init(configuration: CaylexChatConfiguration, layout: DemoLayout,
         refreshToken: @escaping () async throws -> String) {
        self.configuration = configuration
        self.layout = layout
        let controller = CaylexChatController()
        controller.refreshToken = refreshToken
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        switch layout {
        case .fullScreen:
            chat
                .ignoresSafeArea(.container)
                .overlay(alignment: .topTrailing) {
                    Button { dismiss() } label: {
                        Label("Layouts", systemImage: "square.grid.2x2")
                            .font(.caption.weight(.semibold))
                            .padding(10)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 58)
                    .accessibilityIdentifier("show-layouts")
                }
        case .bottomDock:
            VStack(spacing: 0) {
                chat
                dock
            }
            .background(Color(uiColor: .systemBackground))
        case .framed:
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Chat layouts")
                    Spacer()
                    VStack(spacing: 3) {
                        Text("Your assistant").font(.headline)
                        Text("Caylex inside your app").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "person.crop.circle").font(.title2)
                }
                .padding(16)
                chat
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                dock
            }
            .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea(.container))
        }
    }

    private var chat: some View {
        CaylexChatView(configuration: configuration, controller: controller)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dock: some View {
        HStack {
            Button { dismiss() } label: { dockLabel("Home", symbol: "house") }
            Spacer()
            dockLabel("Chat", symbol: "bubble.left.and.bubble.right.fill").foregroundStyle(.tint)
            Spacer()
            Button { dismiss() } label: { dockLabel("Layouts", symbol: "square.grid.2x2") }
                .accessibilityIdentifier("show-layouts")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea(.container, edges: .bottom))
        .overlay(alignment: .top) { Divider() }
    }

    private func dockLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption2)
        }
        .frame(minWidth: 60)
    }
}
