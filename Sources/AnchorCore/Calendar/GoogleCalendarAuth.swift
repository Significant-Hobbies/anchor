import CryptoKit
import Foundation
import PersonalSyncKit
#if canImport(Security)
import Security
#endif

/// Everything Google-side is configured through the app bundle's Info.plist:
/// `GoogleOAuthClientID` is filled at build time from the
/// `GOOGLE_OAUTH_CLIENT_ID` build setting. An empty value means the owner has
/// not supplied Google credentials yet — connect stays off and the settings
/// surface says so instead of failing mid-flow.
public enum GoogleCalendarConfig {
    public static let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!
    public static let apiBaseURL = URL(string: "https://www.googleapis.com/calendar/v3")!
    public static let userInfoURL = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
    public static let redirectPath = "/oauth2callback"

    /// Read-only import plus enough OpenID to name the account. Nothing is
    /// requested that could write to the owner's calendars.
    public static let scopes = [
        "openid",
        "email",
        "https://www.googleapis.com/auth/calendar.readonly",
    ]

    public static func clientID(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String) ?? ""
    }

    public static func isConfigured(bundle: Bundle = .main) -> Bool {
        !clientID(bundle: bundle).isEmpty
    }

    /// Google's installed-app redirect: the reversed client ID is the custom
    /// URL scheme (`com.googleusercontent.apps.<prefix>`), which both app
    /// targets register in their Info.plists.
    public static func callbackScheme(clientID: String) -> String {
        clientID.components(separatedBy: ".").reversed().joined(separator: ".")
    }

    public static func redirectURI(clientID: String) -> String {
        "\(callbackScheme(clientID: clientID)):\(redirectPath)"
    }
}

public enum GoogleCalendarError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case invalidResponse
    case authorizationRejected
    case missingRefreshToken
    case api(status: Int, message: String)
    case keychain(status: Int32)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "Google Calendar is not configured in this build."
        case .invalidResponse: "Google returned an unexpected response."
        case .authorizationRejected: "Google sign-in did not complete."
        case .missingRefreshToken: "Google did not return offline access. Reconnect the account."
        case let .api(status, message): "Google Calendar request failed (\(status)): \(message)"
        case .keychain: "The stored Google session could not be accessed."
        }
    }
}

/// PKCE pair for one authorization attempt. The verifier never leaves the
/// device; the challenge is what Google sees.
public struct GooglePKCE: Sendable, Equatable {
    public var verifier: String
    public var challenge: String

    public init() {
        let verifier = Self.base64URLEncode(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
        self.verifier = verifier
        challenge = Self.base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// One in-flight authorization attempt: the URL to open, the state to expect
/// back, and the verifier the token exchange needs.
public struct GoogleAuthorizationRequest: Sendable, Equatable {
    public var url: URL
    public var state: String
    public var verifier: String
    public var redirectURI: String
}

public extension GoogleCalendarConfig {
    static func makeAuthorizationRequest(
        clientID: String,
        state: String = UUID().uuidString,
        pkce: GooglePKCE = GooglePKCE()
    ) throws -> GoogleAuthorizationRequest {
        guard !clientID.isEmpty else { throw GoogleCalendarError.notConfigured }
        let redirectURI = redirectURI(clientID: clientID)
        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components?.url else { throw GoogleCalendarError.invalidResponse }
        return GoogleAuthorizationRequest(
            url: url,
            state: state,
            verifier: pkce.verifier,
            redirectURI: redirectURI
        )
    }

    /// Extracts the authorization code from the custom-scheme callback,
    /// rejecting callbacks for a different attempt or an explicit denial.
    static func authorizationCode(
        fromCallback url: URL,
        expectedState: String
    ) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else { throw GoogleCalendarError.invalidResponse }
        if items.contains(where: { $0.name == "error" }) {
            throw GoogleCalendarError.authorizationRejected
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else { throw GoogleCalendarError.invalidResponse }
        return code
    }
}

public struct GoogleTokens: Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var idToken: String?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, idToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.idToken = idToken
    }
}

/// The Google account as Google reports it. `id` is the stable `sub` claim —
/// the key for tokens in Keychain and account records in UserDefaults.
public struct GoogleAccountIdentity: Sendable, Equatable {
    public var id: String
    public var email: String
    public var displayName: String

    public init(id: String, email: String, displayName: String) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}

/// Minimal injectable HTTP seam so token exchange, refresh, and the Calendar
/// API are all testable without mocking URLSession internals.
public protocol GoogleHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: GoogleHTTPClient {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.invalidResponse
        }
        return (data, http)
    }
}

/// OAuth token endpoint calls: code exchange, refresh, and revoke. Holds no
/// state — callers own credential persistence.
public struct GoogleTokenClient: Sendable {
    public var http: any GoogleHTTPClient
    public var tokenURL: URL
    public var revokeURL: URL

    public init(
        http: any GoogleHTTPClient = URLSession.shared,
        tokenURL: URL = GoogleCalendarConfig.tokenURL,
        revokeURL: URL = GoogleCalendarConfig.revokeURL
    ) {
        self.http = http
        self.tokenURL = tokenURL
        self.revokeURL = revokeURL
    }

    public func exchange(
        code: String,
        verifier: String,
        redirectURI: String,
        clientID: String,
        now: Date = Date()
    ) async throws -> GoogleTokens {
        try await tokenRequest(
            [
                "grant_type": "authorization_code",
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": redirectURI,
                "client_id": clientID,
            ],
            now: now
        )
    }

    public func refresh(
        _ refreshToken: String,
        clientID: String,
        now: Date = Date()
    ) async throws -> GoogleTokens {
        try await tokenRequest(
            [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
            ],
            now: now
        )
    }

    /// Best-effort revocation on disconnect. Failure here must not block local
    /// cleanup — the account record and Keychain entry go regardless.
    public func revoke(_ token: String) async {
        var components = URLComponents(url: revokeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try? await http.send(request)
    }

    private func tokenRequest(_ fields: [String: String], now: Date) async throws -> GoogleTokens {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleCalendarError.api(
                status: response.statusCode,
                message: (try? JSONDecoder().decode(GoogleErrorBody.self, from: data).errorDescription)
                    ?? "token request failed"
            )
        }
        let body = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GoogleTokens(
            accessToken: body.accessToken,
            refreshToken: body.refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(body.expiresIn)),
            idToken: body.idToken
        )
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case idToken = "id_token"
        }
    }

    struct GoogleErrorBody: Decodable {
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case errorDescription = "error_description"
        }
    }
}

/// Reads the OpenID claims from an ID token returned directly by Google's
/// token endpoint over TLS — display identity only, no signature check needed
/// for that use.
public enum GoogleIDToken {
    public static func identity(from token: String) -> GoogleAccountIdentity? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2,
              let payload = Data(base64URLEncoded: String(segments[1])),
              let claims = try? JSONDecoder().decode(Claims.self, from: payload)
        else { return nil }
        let displayName = claims.name ?? claims.email ?? "Google account"
        return GoogleAccountIdentity(
            id: claims.sub,
            email: claims.email ?? "",
            displayName: displayName
        )
    }

    private struct Claims: Decodable {
        let sub: String
        let email: String?
        let name: String?
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        self.init(base64Encoded: base64)
    }
}

/// Persisted per-account OAuth material. The refresh token is the durable
/// half; the access token is cached to avoid refreshing on every sync.
public struct GoogleCredentials: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        expiresAt <= now.addingTimeInterval(60)
    }
}

/// Per-account credential persistence, keyed by the Google `sub`.
public protocol GoogleCredentialStore: Sendable {
    func load(accountID: String) async throws -> GoogleCredentials?
    func save(_ credentials: GoogleCredentials, accountID: String) async throws
    func delete(accountID: String) async throws
}

#if canImport(Security)
/// Wraps the shared Keychain bearer store — one item per Google account,
/// holding the credentials as a JSON payload.
public actor KeychainGoogleCredentialStore: GoogleCredentialStore {
    private let service: String

    public init(service: String = "com.significanthobbies.anchor.google-calendar") {
        self.service = service
    }

    public func load(accountID: String) async throws -> GoogleCredentials? {
        guard let raw = try await store(for: accountID).load() else { return nil }
        guard let data = raw.data(using: .utf8),
              let credentials = try? JSONDecoder().decode(GoogleCredentials.self, from: data)
        else { return nil }
        return credentials
    }

    public func save(_ credentials: GoogleCredentials, accountID: String) async throws {
        let data = try JSONEncoder().encode(credentials)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw GoogleCalendarError.keychain(status: errSecParam)
        }
        try await store(for: accountID).save(raw)
    }

    public func delete(accountID: String) async throws {
        try await store(for: accountID).delete()
    }

    private func store(for accountID: String) -> KeychainBearerTokenStore {
        KeychainBearerTokenStore(service: service, account: accountID)
    }
}
#endif
