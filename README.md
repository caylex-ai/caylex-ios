# Caylex iOS

Embed the Caylex chat widget in an iOS app using SwiftUI and WKWebView. The
package bundles the existing React widget; it does not require Node.js or a
CDN download in the consuming app.

## Requirements and status

- iOS 16.4 or later; Swift tools 6.0 or later
- No external Swift dependencies
- Tested on an iPhone 16 simulator running iOS 18.3
- First implementation: chat, streamed replies, approvals, session commands,
  token refresh, theming, native navigation callbacks, and lifecycle handling
- Live voice, dictation, attachments, and read-aloud use the web widget's existing
  implementation. Microphone/audio routing, device interruptions, and file-picker
  behavior still require physical-device verification.

## Add the package

In Xcode, open **File → Add Package Dependencies**, enter
`https://github.com/caylex-ai/caylex-ios`, and add the **CaylexChat** product to
your app target. While the repository is private, developers need GitHub access.

Select the `prod` branch for the current stable implementation, or `dev` for development testing. No version tags have
been published yet. A semantic-version tag (for example, `0.1.0`) will let apps
pin a tested release using Xcode's version dependency rules instead of a moving
branch. The Git repository is the distribution source; no App Store submission
or npm installation is needed to consume this Swift package.

## Embed a chat

Obtain a short-lived widget token from your authenticated app backend, then
present this SwiftUI screen. The refresh closure requests a replacement token
from that same backend and is configured before the widget mounts.

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
        // Configure onError, onNavigate, and session callbacks here as needed.
        _chat = StateObject(wrappedValue: controller)

        configuration = CaylexChatConfiguration(
            apiBaseURL: URL(
                string: "https://api.caylex.ai/api/v1/assistants/"
            )!,
            widgetToken: widgetToken
        )
    }

    var body: some View {
        CaylexChatView(
            configuration: configuration,
            controller: chat
        )
        .ignoresSafeArea(.container)
    }
}
```

Your app supplies the `refreshToken` closure; the package does not mint tokens
with platform credentials. The flow is **app → your backend → Caylex token
minting API → widget token returned to the app**. Platform tokens and Caylex API
keys stay on your backend. Only short-lived widget tokens reach the app.

Add the local-networking and microphone entries described under
[Host app configuration](#host-app-configuration) to your app's `Info.plist`.
The view handles chat UI, API requests, and streamed replies without JavaScript
setup in the consuming app.

Keep one controller per mounted chat view. SwiftUI updates to credentials or
appearance preserve the widget's session. Changing the API URL, agent instance,
or tenant user recreates the document and clears its browser storage. For an
account switch where those fields do not change, give the view a new `.id(userID)`
and a separate controller so the previous account's state is discarded.

The view fills its parent and follows SwiftUI's keyboard safe area. Give it a
bounded height when placing it inside another scrolling layout. It does not
force its own navigation bar, sheet, or full-screen presentation.

The host app controls the widget's outer shape with ordinary SwiftUI modifiers:

```swift
CaylexChatView(configuration: config, controller: chat)
    .frame(maxWidth: .infinity)
    .frame(height: 500)
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(.gray.opacity(0.2), lineWidth: 1)
            .allowsHitTesting(false)
    }
    .padding(16)
```

For a top bar or bottom dock, place the chat in the remaining space in a
`VStack(spacing: 0)` and let SwiftUI size it. Keep the default safe-area behavior
for those embedded layouts; use `.ignoresSafeArea(.container)` only when the
chat should extend to the screen edges. Avoid ignoring the keyboard safe area.
Clipping also contains the widget's drawers and popovers inside your chosen shape.

## Sessions and notification routing

```swift
var config = CaylexChatConfiguration(apiBaseURL: apiURL, widgetToken: token)
config.initialSession = .existing(savedSessionID) // Restore on first mount.
// .new explicitly creates a session; .automatic restores browser state if available.

chat.onSessionCreated = { id in /* Save the mapping in your app. */ }
chat.onSessionChanged = { session in /* Observe chat/background-task selection. */ }

// After the view mounts, e.g. after a notification tap:
try await chat.openSession(notificationSessionID)

// Other native commands:
try await chat.sendMessage("Hello")
try await chat.startNewChat()
try await chat.stopGeneration()
try await chat.resume()
try await chat.refresh()
```

Commands wait up to 30 seconds for an attached widget to become ready. The
`status`, `session`, `isExpanded`, `microphoneSupported`, and `realtimeSupported`
properties are observable. Capability flags indicate browser API availability,
not granted permission or a successful live voice connection. Chat/backend errors
are also delivered through `onError`.

`initialSession` applies on first mount. Use `openSession` for later session
changes. Browser storage belongs to an ephemeral WKWebView and is not durable
across app launches; persist session IDs in your host app to restore them later.

Push notifications are the host app's responsibility: register with APNs, send
the device token to your backend, and route notification taps to `openSession`.
The package does not register for push or send notifications. Long-running agent
work must execute durably on the backend, independently of the app's connection.

## Appearance and navigation

Configuration mirrors the web widget's personalization, colors, full/compact
presentation, connected-service button, tool details, memory, and external-session
sync options. The iOS defaults fill the container, remove the card corner radius,
and enable external-session polling while visible.

Pass `navigablePages` and `navigationBaseUrl` to enable agent navigation tools.
`onNavigate` delivers their resolved URL and page name to Swift. Ordinary links
and authentication popups open through `onOpenURL`, or the system browser if
that callback is omitted. After authentication, the widget refreshes connected
services when the app becomes active.

For a full-screen chat, apply `.ignoresSafeArea(.container)` to `CaylexChatView`.
The bundled page uses `viewport-fit=cover` and safe-area insets to keep the
header, composer, and drawer controls clear of the status bar and home indicator,
while drawer backgrounds and backdrops cover the entire screen. Keyboard safe
areas remain managed by SwiftUI.

## Host app configuration

The bundle is served from a random URL path on an ephemeral HTTP listener bound
only to `127.0.0.1`. This gives WebKit a local HTTP origin for its media APIs.
Enable local networking in the host app's `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

For microphone features, also add a description appropriate to your app:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Talk to your assistant.</string>
```

Microphone access is requested only when the user activates a voice control.
iOS Simulator's WebKit uses mock capture devices by default. A successful
`getUserMedia` call or a connected voice session there does not prove it is
receiving your Mac microphone; our iOS 18.3 runtime reports `Mock audio device 1`.
Use a physical iPhone to validate dictation and live voice with real speech.

Camera access is denied. The host app owns any audio-session policies it needs
for mixing, Bluetooth, or other existing audio features. Voice capture stops
when the app enters the background; it is not automatically restarted.

## Transport and lifecycle

A narrowly scoped fetch bridge routes requests under the configured Assistants
API base URL through an ephemeral native URLSession. SSE chunks are forwarded
as they arrive, multipart uploads preserve their bodies, and AbortSignal cancels
native requests. This avoids requiring CORS changes for an embedded origin.
HTTP error statuses stay ordinary responses so the widget's 401 refresh/retry
logic continues to work. Redirects outside the configured API are not followed.
Only HTTPS API URLs are accepted, apart from localhost HTTP for development.

Live voice retains its existing WebRTC media and WebSocket relay. On foreground,
the wrapper refreshes service/task state and wakes session polling. A terminated
WebKit process is reloaded. iOS suspension can interrupt streams; restore or
resume from the backend rather than assuming uninterrupted background execution.

## Demo and development

```sh
swift test
node --test Tests/JavaScript/native-fetch.test.mjs

# Requires XcodeGen to generate the small demo project.
xcodegen generate --spec Examples/ChatDemo/project.yml
python3 Examples/ChatDemo/demo-server.py
open Examples/ChatDemo/ChatDemo.xcodeproj
```

Run the `ChatDemo` scheme on an iPhone simulator with the `--fixture` launch
argument to test the local fixture. Its initial token deliberately expires to
test automatic refresh. The local backend produces clearly labeled
fixture replies, a tool-approval flow, and a saved session. It never calls an AI
provider. The demo opens a layout picker with three pages: full screen, above a
native bottom dock, and a rounded card between a top bar and bottom dock.
Use **Layouts** to return to the picker. Each page owns a separate controller;
returning to the picker closes that mounted chat. The full-screen page's floating
Layouts button is a demo control, not part of the package.
For a direct launch, add `--layout=full`, `--layout=dock`, or `--layout=framed`.

To test a real agent, run the local server
with `--credentials-file /absolute/path/to/private-credentials.json`. That
private file contains `platformToken`, `caylexApiKey`, `userEmail`, `mintURL`, and
`apiBaseURL`, plus an optional `userName`. Use the matching production or development
Caylex endpoints. Keep this file outside the repository with owner-only permissions.
The demo automatically requests a live widget token at launch when this helper is configured; a token-server failure shows a retry screen instead of silently using a fixture.
This helper is for simulator development only; production apps use their own
backend for token minting and refresh.

## Updating the web bundle

The JavaScript source of truth remains in
`caylex-frontend/packages/chat-widget/src/ios-entry.tsx`, using the same widget
component and chat hook as the npm and CDN packages.

```sh
./Scripts/sync-widget.sh /absolute/path/to/caylex-frontend
```

The script type-checks/builds the iOS entry, copies its generated JavaScript,
and records the frontend commit, working-tree state, widget version, and SHA-256
in `Resources/widget-build.json`. Commit the updated bundle with its metadata.
Before a release, build from a clean committed frontend checkout. Consumers
receive the bundled build and do not need access to the frontend repository.

CI tests configuration encoding and the streaming bridge, checks the bundle
checksum, and compiles the iOS demo. No credentials are required.

## Development and production releases

- `dev` receives Swift changes and reviewed frontend bundle sync PRs.
- `prod` contains approved production code. Promote with a `dev` → `prod` PR.
- Swift package release versions are independent of the bundled widget's npm version.

After merging a promotion PR, select **Actions → Publish iOS release → Run workflow**,
choose **prod**, and enter a new stable version such as `0.1.0` (without `v`).
The workflow validates bundle provenance, runs package/bridge tests, and compiles
both device and simulator builds before creating `v0.1.0` and a GitHub release.
It rejects existing or older versions and refuses publication if `prod` changes
while checks are running. It does not merge branches or change repository visibility.

Install production releases in Xcode using a version dependency rule once the first
tag exists. The repository remains a source package; private consumers need repository
access for local development and CI. There is no binary SDK upload in this workflow.

Frontend production (`prod`) changes automatically open or update `automation/sync-widget` → `dev`
in this repository after the frontend sync workflow is installed and its cross-repo
credential is configured. Review those PRs after package checks pass, then promote
and release when ready. Native-only improvements can be released without changing
the bundled web widget.

Bootstrap the workflow by merging its setup PR into `dev`, then promoting `dev`
to `prod`. Make `prod` the default branch so the manual release action is available.
Keep `main` temporarily for existing branch-based consumers; it is a legacy snapshot,
not a release channel. Protect `dev` and `prod` with required PRs and package checks
in repository settings according to your organization's policy.

The frontend workflow uses `CAYLEX_IOS_SYNC_TOKEN` (Contents and Pull requests write
access to this repository) stored in `caylex-frontend` Actions secrets. See
`caylex-frontend/docs/ios-widget-sync.md` for setup and rollout order.
