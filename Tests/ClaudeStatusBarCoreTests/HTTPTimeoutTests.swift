// Tests/ClaudeStatusBarCoreTests/HTTPTimeoutTests.swift
//
// A request that hangs — the usual shape right after the Mac wakes with a half-up
// network — used to sit there for URLRequest's default 60 seconds, holding the
// account's tile on a stale state for a whole minute. These pin the deadline down.
import Testing
import Foundation
@testable import ClaudeStatusBarCore

/// Captures the request URLSession actually sends. A `/hang` path is never answered,
/// which is how a stuck request is simulated.
///
/// Behaviour is keyed off the URL rather than a shared flag on purpose: swift-testing
/// runs these in parallel, and a mutable static would have one test silently reconfigure
/// the other's stub.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var captured: [URLRequest] = []

    /// Requests seen for a given path, so parallel tests never read each other's.
    static func requests(path: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return captured.filter { $0.url?.path == path }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.captured.append(request)
        Self.lock.unlock()
        guard request.url?.path != "/hang" else { return }   // never call the client
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedClient(timeout: TimeInterval) -> URLSessionHTTPClient {
    let cfg = URLSessionHTTPClient.configuration(timeout: timeout)
    cfg.protocolClasses = [StubURLProtocol.self]
    return URLSessionHTTPClient(session: URLSession(configuration: cfg), timeout: timeout)
}

@Test func send_stampsItsOwnDeadlineOverURLRequestsSixtySecondDefault() async throws {
    let client = stubbedClient(timeout: 7)
    let req = URLRequest(url: URL(string: "https://example.invalid/usage")!)
    #expect(req.timeoutInterval == 60)   // what every caller in this package builds

    _ = try await client.send(req)

    let sent = try #require(StubURLProtocol.requests(path: "/usage").first)
    #expect(sent.timeoutInterval == 7)
}

@Test func send_givesUpOnAHungRequestWithinTheDeadline() async throws {
    let client = stubbedClient(timeout: 0.5)
    let started = Date()

    await #expect(throws: (any Error).self) {
        _ = try await client.send(URLRequest(url: URL(string: "https://example.invalid/hang")!))
    }

    // Comfortably under URLRequest's 60s default; the point is that it ends at all.
    #expect(Date().timeIntervalSince(started) < 10)
}

@Test func configuration_boundsBothTheIdleGapAndTheWholeTransfer() {
    let cfg = URLSessionHTTPClient.configuration(timeout: 20)
    #expect(cfg.timeoutIntervalForRequest == 20)
    // The per-request value only limits gaps between packets, so a slow drip needs its
    // own ceiling or it runs indefinitely.
    #expect(cfg.timeoutIntervalForResource == 40)
    // Fail fast instead of parking the request until the network returns — the poll
    // loop will come back on its own, and a parked request is what stales a tile.
    #expect(cfg.waitsForConnectivity == false)
}

@Test func defaultTimeout_isShorterThanTheShortestSyncInterval() {
    // A request must never still be in flight when the next poll for the same account
    // starts, or the two race for the same tile.
    #expect(URLSessionHTTPClient.defaultTimeout < TimeInterval(Account.intervalFloor))
}
