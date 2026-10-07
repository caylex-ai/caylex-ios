# Caylex iOS

An embeddable iOS chat component backed by the Caylex web chat widget.

## Status

Initial package scaffold. The package builds, but the chat view, JavaScript
bridge, widget bundle, and demo app are not implemented yet.

## Package

- Swift tools: 6.0 or later
- Intended deployment target: iOS 15 or later (to be verified during implementation)
- Library product and module: `CaylexChat`
- No external Swift dependencies

Add `https://github.com/caylex-ai/caylex-ios` through Xcode's package dependency
settings. While the repository is private, consumers need repository access.
Use the `main` branch during development; versioned releases will follow.

## Layout

```text
Package.swift
Sources/CaylexChat/
  CaylexChatConfiguration.swift
  Internal/                       # WKWebView and JavaScript bridge
  Resources/index.html            # Embedded widget host
Tests/CaylexChatTests/             # Future bridge and lifecycle tests
Examples/ChatDemo/                 # Future iOS demo application
```

## Architecture

The React widget remains in `caylex-frontend/packages/chat-widget` as the single
source of chat behavior. Each iOS release will bundle a specific generated
widget build alongside the HTML host. Consumers will not need Node.js.

This package will provide a SwiftUI view, chat controller, and a bridge for
configuration, token refresh, session changes, and navigation. The host app
owns push notification registration and notification-tap routing. Backend
services own notification delivery and durable task execution.

Widget tokens must be minted by the host application's backend. Never embed
platform credentials or Caylex API keys in the app or resource bundle.

## Development

```sh
swift build
```

Implementation milestones:

1. Add the SwiftUI/WKWebView container and a demo app.
2. Add the JavaScript bridge and bundle the existing web widget.
3. Wire token refresh, session control, navigation, and app lifecycle handling.
4. Verify keyboard, authentication, attachments, and live voice on an iPhone.
5. Add release automation to pin and verify the bundled widget version.
