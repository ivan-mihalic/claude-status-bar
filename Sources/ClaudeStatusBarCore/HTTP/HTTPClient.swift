import Foundation

public struct HTTPResponse: Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status; self.headers = headers; self.body = body
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    /// Every call this app makes is a small JSON round-trip. `URLRequest`'s own default
    /// is 60s, which is long enough for a request that hangs — the usual shape right
    /// after the Mac wakes with a half-up network — to still be in flight when the next
    /// poll starts, so the two race for the same tile. 20s is far past a healthy
    /// response and safely inside the 60s floor on a sync interval.
    public static let defaultTimeout: TimeInterval = 20

    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession, timeout: TimeInterval = defaultTimeout) {
        self.session = session; self.timeout = timeout
    }

    public init(timeout: TimeInterval = defaultTimeout) {
        self.init(session: URLSession(configuration: Self.configuration(timeout: timeout)),
                  timeout: timeout)
    }

    public static func configuration(timeout: TimeInterval) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = timeout
        // The per-request value only bounds gaps between packets; without this a slow
        // drip would never end on its own.
        c.timeoutIntervalForResource = timeout * 2
        // Fail fast rather than parking the request until connectivity returns — the
        // poll loop comes back by itself, and a parked request is what strands a tile.
        c.waitsForConnectivity = false
        return c
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        // Stamped on the request as well as on the configuration: callers build plain
        // `URLRequest`s, which carry their own 60s default, and which of the two wins
        // isn't worth depending on.
        var request = request
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let ks = k as? String, let vs = v as? String { headers[ks] = vs }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }
}
