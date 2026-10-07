import Foundation

public enum CaylexInitialSession: Equatable, Sendable {
    case automatic
    case new
    case existing(String)
}

public struct CaylexNavigablePage: Encodable, Equatable, Sendable {
    public struct Parameter: Encodable, Equatable, Sendable {
        public var description: String
        public var required: Bool
        public var defaultValue: String?

        public init(description: String, required: Bool = false, defaultValue: String? = nil) {
            self.description = description
            self.required = required
            self.defaultValue = defaultValue
        }
    }

    public var name: String
    public var description: String?
    public var urlTemplate: String
    public var templateParams: [String: Parameter]?
    public var queryParams: [String: Parameter]?

    public init(name: String, description: String? = nil, urlTemplate: String,
                templateParams: [String: Parameter]? = nil, queryParams: [String: Parameter]? = nil) {
        self.name = name
        self.description = description
        self.urlTemplate = urlTemplate
        self.templateParams = templateParams
        self.queryParams = queryParams
    }
}

/// Configuration for the bundled Caylex web widget. Mint tokens on your backend.
public struct CaylexChatConfiguration: Encodable, Equatable, Sendable {
    public enum Theme: String, Encodable, Sendable { case light, dark }
    public enum Presentation: String, Encodable, Sendable { case full, compact }

    public var apiBaseURL: URL
    public var widgetToken: String
    public var userName = ""
    public var sampleQueries: [String] = []
    public var theme: Theme = .light
    public var primaryColor = "#3F58CF"
    public var backgroundColor = "#FFFFFF"
    public var darkPrimaryColor: String?
    public var darkBackgroundColor: String?
    public var borderRadius = 0
    public var presentation: Presentation = .full
    public var enableCompactMode = false
    public var showToolCallDetails = false
    public var showServersButton = true
    public var enableExternalSessionSync = true
    public var externalSessionSyncIntervalMs = 5000
    public var sessionName = "Chat"
    public var embedMessages = true
    public var agentInstanceId: String?
    public var tenantUserId: String?
    public var initialSession: CaylexInitialSession = .automatic
    public var navigablePages: [CaylexNavigablePage] = []
    public var navigationBaseUrl: String?

    public init(apiBaseURL: URL, widgetToken: String) {
        self.apiBaseURL = apiBaseURL
        self.widgetToken = widgetToken
    }

    enum CodingKeys: String, CodingKey {
        case apiBaseUrl, widgetToken, userName, sampleQueries, theme, primaryColor, backgroundColor
        case darkPrimaryColor, darkBackgroundColor, borderRadius, presentation, enableCompactMode
        case showToolCallDetails, showServersButton, enableExternalSessionSync, externalSessionSyncIntervalMs
        case sessionName, embedMessages, agentInstanceId, tenantUserId, initialSessionId
        case navigablePages, navigationBaseUrl, height, width, compactWidth
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let base = apiBaseURL.absoluteString
        try c.encode(base.hasSuffix("/") ? base : base + "/", forKey: .apiBaseUrl)
        try c.encode(widgetToken, forKey: .widgetToken)
        try c.encode(userName, forKey: .userName)
        try c.encode(sampleQueries, forKey: .sampleQueries)
        try c.encode(theme, forKey: .theme)
        try c.encode(primaryColor, forKey: .primaryColor)
        try c.encode(backgroundColor, forKey: .backgroundColor)
        try c.encodeIfPresent(darkPrimaryColor, forKey: .darkPrimaryColor)
        try c.encodeIfPresent(darkBackgroundColor, forKey: .darkBackgroundColor)
        try c.encode(borderRadius, forKey: .borderRadius)
        try c.encode(presentation, forKey: .presentation)
        try c.encode(enableCompactMode, forKey: .enableCompactMode)
        try c.encode(showToolCallDetails, forKey: .showToolCallDetails)
        try c.encode(showServersButton, forKey: .showServersButton)
        try c.encode(enableExternalSessionSync, forKey: .enableExternalSessionSync)
        try c.encode(externalSessionSyncIntervalMs, forKey: .externalSessionSyncIntervalMs)
        try c.encode(sessionName, forKey: .sessionName)
        try c.encode(embedMessages, forKey: .embedMessages)
        try c.encodeIfPresent(agentInstanceId, forKey: .agentInstanceId)
        try c.encodeIfPresent(tenantUserId, forKey: .tenantUserId)
        try c.encode(navigablePages, forKey: .navigablePages)
        try c.encodeIfPresent(navigationBaseUrl, forKey: .navigationBaseUrl)
        try c.encode("100%", forKey: .height)
        try c.encode("100%", forKey: .width)
        try c.encode("100%", forKey: .compactWidth)
        switch initialSession {
        case .automatic: break
        case .new: try c.encodeNil(forKey: .initialSessionId)
        case .existing(let id): try c.encode(id, forKey: .initialSessionId)
        }
    }

    func validate() throws {
        guard let scheme = apiBaseURL.scheme, let host = apiBaseURL.host,
              apiBaseURL.user == nil, apiBaseURL.password == nil,
              apiBaseURL.query == nil, apiBaseURL.fragment == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw CaylexChatError.invalidConfiguration("Use an HTTPS API URL, or localhost HTTP for development")
        }
        guard !widgetToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaylexChatError.invalidConfiguration("A widget token is required")
        }
        if case .existing(let id) = initialSession, id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CaylexChatError.invalidConfiguration("The initial session ID cannot be empty")
        }
        if !navigablePages.isEmpty && (navigationBaseUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            throw CaylexChatError.invalidConfiguration("navigationBaseUrl is required for navigable pages")
        }
    }
}
