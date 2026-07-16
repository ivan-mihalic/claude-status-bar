// Sources/ClaudeStatusBarCore/Usage/UsageDTO.swift
import Foundation

public struct UsageWindowDTO: Decodable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date
    enum CodingKeys: String, CodingKey { case utilization; case resetsAt = "resets_at" }
}

public struct UsageResponseDTO: Decodable, Sendable {
    public let windows: [String: UsageWindowDTO]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var result: [String: UsageWindowDTO] = [:]
        for key in container.allKeys {
            // Try to decode each value as a window; skip nulls and other shapes.
            if let w = try? container.decode(UsageWindowDTO.self, forKey: key) {
                result[key.stringValue] = w
            }
        }
        self.windows = result
    }
}

public enum UsageJSON {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmtNoFrac = ISO8601DateFormatter()
        fmtNoFrac.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = fmt.date(from: s) ?? fmtNoFrac.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }
}
