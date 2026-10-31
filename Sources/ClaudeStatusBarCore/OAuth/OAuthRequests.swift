// Sources/ClaudeStatusBarCore/OAuth/OAuthRequests.swift
import Foundation

public enum OAuthRequests {
    private static func form(_ pairs: [(String, String)]) -> Data {
        var comps = URLComponents()
        comps.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        // percentEncodedQuery uses form encoding; ensure "+" in values is escaped.
        let s = (comps.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B")
        return Data(s.utf8)
    }

    private static func post(_ url: URL, _ pairs: [(String, String)]) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = form(pairs)
        return req
    }

    public static func exchange(tokenURL: URL, config: OAuthConfig,
                                code: String, verifier: String,
                                state: String?, redirectURI: String? = nil) -> URLRequest {
        var pairs = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI ?? config.redirectURI),
            ("client_id", config.clientID),
            ("code_verifier", verifier),
        ]
        if let state { pairs.append(("state", state)) }
        return post(tokenURL, pairs)
    }

    public static func refresh(tokenURL: URL, config: OAuthConfig,
                               refreshToken: String) -> URLRequest {
        post(tokenURL, [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", config.clientID),
        ])
    }
}
