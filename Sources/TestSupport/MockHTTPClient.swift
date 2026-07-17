import Foundation
import ClaudeStatusBarCore

public final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    public var handler: (URLRequest) throws -> HTTPResponse
    public private(set) var requests: [URLRequest] = []
    public var lastRequest: URLRequest? { requests.last }

    public init(handler: @escaping (URLRequest) throws -> HTTPResponse = { _ in
        HTTPResponse(status: 200, headers: [:], body: Data())
    }) { self.handler = handler }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try handler(request)
    }
}
