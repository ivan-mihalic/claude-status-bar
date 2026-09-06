// Sources/ClaudeStatusBarApp/Accounts/OAuthLoginService.swift
import Foundation
import ClaudeStatusBarCore

public struct PendingLogin: Sendable {
    public let pkce: PKCE
    public let state: String
    public let authorizeURL: URL
    public let provider: Provider

    public init(pkce: PKCE, state: String, authorizeURL: URL, provider: Provider = .claude) {
        self.pkce = pkce; self.state = state
        self.authorizeURL = authorizeURL; self.provider = provider
    }
}

public enum LoginError: Error, Equatable {
    /// The redirect came back with a `state` that isn't the one we sent — the response
    /// belongs to a different sign-in attempt, so the code must not be exchanged.
    case stateMismatch
    /// Codex's redirect is a fixed loopback address; if something else holds the port
    /// (`codex login` running in a terminal, most likely) there is nowhere to catch it.
    case callbackPortBusy(UInt16)
    case cancelled(String)
    case timedOut
}

extension LoginError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .stateMismatch: return "The sign-in response did not match this login attempt."
        case .callbackPortBusy(let port):
            return "Port \(port) is already in use. Close another Codex login and try again."
        case .cancelled(let reason): return "Sign-in was cancelled: \(reason)"
        case .timedOut: return "Sign-in did not finish within five minutes."
        }
    }
}

/// Everything one provider needs to run a browser sign-in.
public struct LoginBackend: Sendable {
    public let oauth: OAuthClient
    public let endpoints: OAuthEndpoints
    public let config: OAuthConfig
    public let deviceCode: DeviceCodeAuthClient?

    public init(oauth: OAuthClient, endpoints: OAuthEndpoints, config: OAuthConfig,
                deviceCode: DeviceCodeAuthClient? = nil) {
        self.oauth = oauth; self.endpoints = endpoints; self.config = config
        self.deviceCode = deviceCode
    }
}

public struct OAuthLoginService {
    private let backends: [Provider: LoginBackend]
    private let tokenStore: TokenStore
    private let opener: BrowserOpener

    public init(backends: [Provider: LoginBackend], tokenStore: TokenStore,
                opener: BrowserOpener) {
        self.backends = backends; self.tokenStore = tokenStore; self.opener = opener
    }

    public init(oauth: OAuthClient, endpoints: OAuthEndpoints, config: OAuthConfig,
                tokenStore: TokenStore, opener: BrowserOpener) {
        self.init(backends: [.claude: LoginBackend(oauth: oauth, endpoints: endpoints,
                                                   config: config)],
                  tokenStore: tokenStore, opener: opener)
    }

    public func backend(for provider: Provider) -> LoginBackend? { backends[provider] }

    public func begin(provider: Provider = .claude) -> PendingLogin? {
        guard let backend = backends[provider] else { return nil }
        let pkce = PKCE.generate()
        let state = PKCE.generate().verifier          // reuse CSPRNG for an opaque state
        let url = backend.endpoints.authorizeURL(config: backend.config, pkce: pkce, state: state)
        // A loopback flow opens the browser only after its listener reports ready. Opening
        // it here creates a race in which a fast redirect reaches an unbound port.
        if URL(string: backend.config.redirectURI)?.host != "localhost" {
            opener.open(url)
        }
        return PendingLogin(pkce: pkce, state: state, authorizeURL: url, provider: provider)
    }

    public func beginDeviceCode(provider: Provider) async throws -> DeviceCodeLogin {
        guard let device = backends[provider]?.deviceCode else { throw DeviceCodeError.unavailable }
        let login = try await device.requestCode()
        opener.open(login.verificationURL)
        return login
    }

    public func completeDeviceCode(_ deviceLogin: DeviceCodeLogin, provider: Provider,
                                   accountID: UUID) async throws -> TokenBundle {
        guard let device = backends[provider]?.deviceCode else { throw DeviceCodeError.unavailable }
        let bundle = try await device.complete(deviceLogin)
        try tokenStore.save(bundle, for: accountID)
        return bundle
    }

    /// The Codex half: opens the browser, waits for its own loopback redirect, and files the
    /// token. No code is ever pasted — the provider's redirect URI cannot be changed to a
    /// page that displays one.
    public func completeViaLoopback(_ pending: PendingLogin, accountID: UUID,
                                    timeout: TimeInterval = 300) async throws -> TokenBundle {
        guard let backend = backends[pending.provider],
              let server = LoopbackCallbackServer(redirectURI: backend.config.redirectURI) else {
            throw AccountError.unknownAccount
        }
        let callback: LoopbackCallbackServer.Callback
        do {
            callback = try await server.waitForCallback(timeout: timeout) {
                opener.open(pending.authorizeURL)
            }
        } catch LoopbackCallbackServer.Failure.portUnavailable(let port) {
            throw LoginError.callbackPortBusy(port)
        } catch LoopbackCallbackServer.Failure.authorizationDenied(let why) {
            throw LoginError.cancelled(why)
        } catch LoopbackCallbackServer.Failure.timedOut {
            throw LoginError.timedOut
        }
        // A redirect whose state isn't ours belongs to someone else's sign-in; exchanging its
        // code would file a stranger's token under this account.
        guard callback.state == pending.state else {
            throw LoginError.stateMismatch
        }
        let bundle = try await backend.oauth.exchange(code: callback.code,
                                                     verifier: pending.pkce.verifier,
                                                     state: pending.state)
        try tokenStore.save(bundle, for: accountID)
        return bundle
    }

    public func complete(_ pending: PendingLogin, code rawCode: String,
                         accountID: UUID) async throws -> TokenBundle {
        // Anthropic's callback page shows "<code>#<state>" or "<code>&state=<state>";
        // accept a pasted value that may include either separator.
        let code = rawCode
            .split(whereSeparator: { $0 == "#" || $0 == "&" }).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawCode
        guard let backend = backends[pending.provider] else { throw AccountError.unknownAccount }
        let bundle = try await backend.oauth.exchange(code: code, verifier: pending.pkce.verifier,
                                                     state: pending.state)
        try tokenStore.save(bundle, for: accountID)
        return bundle
    }
}
