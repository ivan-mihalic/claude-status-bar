import Foundation
@testable import ClaudeStatusBarCore

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    var handler: (URLRequest) throws -> HTTPResponse
    private(set) var requests: [URLRequest] = []
    var lastRequest: URLRequest? { requests.last }

    init(handler: @escaping (URLRequest) throws -> HTTPResponse = { _ in
        HTTPResponse(status: 200, headers: [:], body: Data())
    }) { self.handler = handler }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try handler(request)
    }
}
