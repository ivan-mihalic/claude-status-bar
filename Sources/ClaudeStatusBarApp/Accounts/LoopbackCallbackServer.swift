// Sources/ClaudeStatusBarApp/Accounts/LoopbackCallbackServer.swift
import Foundation
import Network

/// Catches one OAuth redirect on `127.0.0.1` and then shuts down.
///
/// It exists only because the Codex OAuth client's redirect URI is a fixed loopback address
/// that cannot be changed from here — the Anthropic flow shows the code on a web page and
/// needs no listener at all. It is deliberately the smallest thing that can work: bound to
/// the loopback interface, alive for one request, closed as soon as the code is in hand or
/// the timeout expires.
public actor LoopbackCallbackServer {
    public enum Failure: Error, Equatable {
        /// Something else holds the port — most likely a `codex login` running right now.
        case portUnavailable(UInt16)
        /// The browser never came back before the deadline.
        case timedOut
        /// The provider redirected with an error instead of a code.
        case authorizationDenied(String)
        case cancelled
    }

    /// What the redirect carried. `state` is checked by the caller against the value it sent.
    public struct Callback: Equatable, Sendable {
        public let code: String
        public let state: String?
    }

    private let port: UInt16
    private let path: String
    private var listener: NWListener?

    public init(port: UInt16, path: String) {
        self.port = port; self.path = path
    }

    /// Convenience: take both from the OAuth config's redirect URI, so the listener can never
    /// disagree with the address the provider was told to redirect to.
    public init?(redirectURI: String) {
        guard let comps = URLComponents(string: redirectURI),
              let p = comps.port, p > 0, p <= 65_535,
              comps.host == "localhost" || comps.host == "127.0.0.1" else { return nil }
        self.init(port: UInt16(p), path: comps.path.isEmpty ? "/" : comps.path)
    }

    /// Parses the request line of an HTTP request into the callback it carries.
    ///
    /// Split out as a pure function because it is the part worth testing: the socket work is
    /// plumbing, but a redirect carrying `error=access_denied` must never be mistaken for a
    /// successful sign-in.
    public static func parse(requestLine: String, expectedPath: String)
        -> Result<Callback, Failure>? {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let comps = URLComponents(string: "http://localhost" + parts[1]),
              comps.path == expectedPath else { return nil }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            // `URLComponents` percent-decodes but leaves "+" alone, and providers form-encode
            // spaces that way — an error description would otherwise reach the user as
            // "User+said+no".
            items.first { $0.name == name }?.value
                .map { $0.replacingOccurrences(of: "+", with: " ") }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        if let error = value("error") {
            return .failure(.authorizationDenied(value("error_description") ?? error))
        }
        guard let code = value("code") else { return nil }
        return .success(Callback(code: code, state: value("state")))
    }

    private static func response(body: String) -> Data {
        let html = """
        <!doctype html><meta charset="utf-8"><title>Claude Status Bar</title>
        <body style="font:16px -apple-system,sans-serif;padding:3rem;text-align:center">
        <p>\(body)</p></body>
        """
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r

        """
        return Data(headers.utf8) + Data(html.utf8)
    }

    /// Starts listening and resolves with the first valid callback. Always stops itself.
    public func waitForCallback(timeout: TimeInterval = 300) async throws -> Callback {
        defer { stop() }
        return try await withThrowingTaskGroup(of: Callback.self) { group in
            group.addTask { try await self.listen() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw Failure.timedOut
            }
            guard let first = try await group.next() else { throw Failure.cancelled }
            group.cancelAll()
            return first
        }
    }

    private func listen() async throws -> Callback {
        let params = NWParameters.tcp
        // Loopback only. A listener reachable from the network would be a far bigger promise
        // than "catch my own browser redirect".
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw Failure.portUnavailable(port)
        }
        let listener = try { () throws -> NWListener in
            do { return try NWListener(using: params, on: nwPort) }
            catch { throw Failure.portUnavailable(port) }
        }()
        self.listener = listener

        let expectedPath = path
        return try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            listener.stateUpdateHandler = { state in
                if case .failed = state { box.resume(throwing: Failure.portUnavailable(self.port)) }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                    data, _, _, _ in
                    let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let line = text.split(separator: "\r\n", maxSplits: 1,
                                          omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    switch Self.parse(requestLine: line, expectedPath: expectedPath) {
                    case .success(let callback):
                        connection.send(content: Self.response(body: "Signed in. You can close this tab."),
                                        completion: .contentProcessed { _ in connection.cancel() })
                        box.resume(returning: callback)
                    case .failure(let failure):
                        connection.send(content: Self.response(body: "Sign-in was cancelled."),
                                        completion: .contentProcessed { _ in connection.cancel() })
                        box.resume(throwing: failure)
                    case nil:
                        // Some other request hit the port — answer politely and keep waiting.
                        connection.send(content: Self.response(body: "Waiting for the sign-in redirect…"),
                                        completion: .contentProcessed { _ in connection.cancel() })
                    }
                }
            }
            listener.start(queue: .main)
        }
    }

    public nonisolated func stopFromAnywhere() { Task { await self.stopActor() } }
    private func stopActor() { stop() }

    private func stop() {
        listener?.cancel()
        listener = nil
    }
}

/// Guards a continuation against the double-resume that a socket callback firing twice would
/// otherwise cause — that is a crash, not a warning.
private final class ContinuationBox: @unchecked Sendable {
    private var continuation: CheckedContinuation<LoopbackCallbackServer.Callback, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<LoopbackCallbackServer.Callback, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: LoopbackCallbackServer.Callback) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(throwing: error)
    }
}
