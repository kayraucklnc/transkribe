import Foundation

/// Removes Whisper's runaway repetition loops ("olununununun…", "thank you. thank you. …")
/// while leaving natural repetition ("no no no", "hahaha") alone.
public enum RepetitionFilter {
    /// A chunk of 2–40 characters repeated four or more times in a row.
    private static let repeatedChunk = try! NSRegularExpression(pattern: #"(.{2,40}?)\1{3,}"#, options: [.caseInsensitive])
    /// A single character repeated eight or more times.
    private static let repeatedCharacter = try! NSRegularExpression(pattern: #"(.)\1{7,}"#)

    public static func collapse(_ text: String) -> String {
        var result = text
        for regex in [repeatedChunk, repeatedCharacter] {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1"
            )
        }
        return result
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
