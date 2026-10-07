import Foundation

/// Credentials used to connect the embedded chat to Caylex.
///
/// Obtain widget tokens from your application's backend. Platform credentials
/// and Caylex API keys must remain on the backend.
public struct CaylexChatConfiguration: Sendable {
    /// Assistants API base URL, including its trailing slash.
    public var apiBaseURL: URL

    /// Short-lived widget token minted by your backend.
    public var widgetToken: String

    public init(apiBaseURL: URL, widgetToken: String) {
        self.apiBaseURL = apiBaseURL
        self.widgetToken = widgetToken
    }
}
