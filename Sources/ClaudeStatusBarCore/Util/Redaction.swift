// Sources/ClaudeStatusBarCore/Util/Redaction.swift
import Foundation

public enum Redaction {
    // Matches sk-ant-<kind>01- followed by the secret body; keeps the prefix, masks the body.
    private static let pattern = try! NSRegularExpression(
        pattern: "(sk-ant-[a-z]+[0-9]*-)[A-Za-z0-9._-]+"
    )

    public static func redact(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(
            in: text, range: range, withTemplate: "$1***"
        )
    }
}
