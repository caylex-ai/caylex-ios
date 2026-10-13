# Caylex iOS

Embed the Caylex Agent Widget in your iOS app with SwiftUI. `CaylexChatView`
bundles the same chat UI as the web widget and renders it in a `WKWebView`, with
Swift controls for sessions, token refresh, and navigation. It supports streamed
replies, tool approvals, connected services, and saved conversations.

## Requirements

- iOS 16.4 or later and Swift tools 6.0 or later
- A Caylex navigator and an authenticated backend that provides widget tokens

## Install

In Xcode, select **File → Add Package Dependencies**, enter
`https://github.com/caylex-ai/caylex-ios`, and add **CaylexChat** to your app target.
The repository is public; no invitation, npm installation, or access to the
private frontend repository is required.

No releases are tagged yet. Select the **main** branch to try the package.
Once the first release is published, pin a tested version using Xcode's version
rules for production apps. Use `dev` only for development testing.

## Configure your app

Add this entry to your app's `Info.plist`. If `NSAppTransportSecurity` already
exists, add the local-networking key to that dictionary. The package serves its
bundled UI locally on `127.0.0.1`.

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

For dictation or live voice, also add:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Talk to your assistant.</string>
```

## Embed a chat

Fetch a short-lived widget token from your authenticated backend before showing
this screen. Supply a `refreshToken` closure that requests a replacement from
that same backend. Platform tokens and navigator API keys stay on your backend;
only widget tokens reach the app.

```swift
import SwiftUI
import CaylexChat

@MainActor
struct ChatScreen: View {
    @StateObject private var chat: CaylexChatController
    private let configuration: CaylexChatConfiguration

    init(
        widgetToken: String,
        refreshToken: @escaping () async throws -> String
    ) {
        let controller = CaylexChatController()
        controller.refreshToken = refreshToken
        _chat = StateObject(wrappedValue: controller)

        configuration = CaylexChatConfiguration(
            apiBaseURL: URL(
                string: "https://api.caylex.ai/api/v1/assistants/"
            )!,
            widgetToken: widgetToken
        )
    }

    var body: some View {
        CaylexChatView(configuration: configuration, controller: chat)
            .ignoresSafeArea(.container)
    }
}
```

Your app provides the token-fetching function; the package does not mint tokens
with platform credentials. Keep one controller per mounted view, and configure
its callbacks before mounting. For a development navigator, use
`https://api.caylex.dev/api/v1/assistants/` with matching development tokens.

## Fit your layout

The chat fills its parent. For full screen, use `.ignoresSafeArea(.container)`
as above, leaving the keyboard safe area enabled. For a top bar or bottom dock,
place the chat in the remaining space in a `VStack(spacing: 0)` and keep its
default safe-area behavior.

For a card, control its height and outer shape with SwiftUI:

```swift
CaylexChatView(configuration: configuration, controller: chat)
    .frame(maxWidth: .infinity)
    .frame(height: 500)
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .padding(16)
```

Clipping also contains drawers and popovers. Give the chat a bounded height when
placing it inside another scrolling layout.

## Customize and control the widget

Set appearance and the initial session before mounting:

```swift
var config = CaylexChatConfiguration(apiBaseURL: apiURL, widgetToken: token)
config.userName = "Jane"
config.sampleQueries = ["Show me recent orders"]
config.theme = .dark
config.darkBackgroundColor = "#15151C"
config.showToolCallDetails = false
config.initialSession = .existing(savedSessionID)
// .new starts a fresh session; .automatic restores web storage when available.
```

Use the controller from an async task and handle thrown errors:

```swift
try await chat.openSession(savedSessionID)
try await chat.sendMessage("Hello")
try await chat.startNewChat()
try await chat.stopGeneration()
try await chat.resume()
try await chat.refresh()
```

`initialSession` applies on first mount. Persist session IDs in your app or
backend to restore conversations across launches; the web view's storage is
ephemeral. Configure `onSessionCreated` and `onSessionChanged` to track sessions,
and `onError` for error handling. Use a separate controller and a new view
identity, such as `.id(userID)`, when switching accounts.

Pass `navigablePages` and `navigationBaseUrl`, then handle `onNavigate` for
agent-driven app navigation. External links and authentication flows open in
the system browser by default, or through your `onOpenURL` callback.

See [configuration options](Sources/CaylexChat/CaylexChatConfiguration.swift)
and [controller callbacks and state](Sources/CaylexChat/CaylexChatController.swift)
for the full API.

## Voice, notifications, and updates

Validate dictation, live voice, audio routing, attachments, and read-aloud on a
physical iPhone. Simulator microphone capture may use mock audio devices, and
these features still require physical-device verification. Voice capture stops
when the app enters the background and does not restart automatically.

Your app owns APNs registration and notification delivery. Route notification
taps to `chat.openSession(sessionID)` after the view mounts. Background agent
work runs on the backend; app suspension can interrupt streams.

The package ships a bundled snapshot of the web widget. To deliver improvements
to installed apps, update the Swift package dependency and ship an app update.

## Contributing

See the [development guide](docs/DEVELOPMENT.md) for the demo app, tests, bundle
syncing, transport details, and release workflow. App developers do not need
these tools to consume the package.
