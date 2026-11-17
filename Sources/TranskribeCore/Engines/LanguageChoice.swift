import Foundation

/// Which of the user's languages a stretch of audio is in, from Whisper's guesses on samples of it.
///
/// A conversation rarely changes language, and one short guess is often wrong (20 seconds of a
/// Turkish call came back as English, went to the European model, and became nonsense). So the
/// language so far is kept unless the evidence is strong (several samples, two thirds agreeing),
/// or two stretches in a row point to the same new language.
public struct LanguageChoice: Sendable, Equatable {
    public private(set) var current: String?
    /// A different language the last stretch pointed to; confirmed if the next one does too.
    public private(set) var candidate: String?

    static let strongVotes = 3
    static let strongShare = 2.0 / 3.0

    public init(current: String? = nil) {
        self.current = current
    }

    public mutating func choose(votes: [String], supported: Set<String>) -> String? {
        guard !supported.isEmpty else { return votes.first ?? current }
        let usable = votes.filter(supported.contains)
        let counts = Dictionary(usable.map { ($0, 1) }, uniquingKeysWith: +)
        // Most votes; ties go to the language so far, then alphabetical, so it's stable.
        guard let winner = counts.max(by: { a, b in
            a.value != b.value ? a.value < b.value : (a.key == current) != (b.key == current) ? b.key == current : a.key > b.key
        })?.key else {
            if current == nil { current = supported.sorted().first }
            return current
        }
        guard let established = current, supported.contains(established) else {
            current = winner
            return winner
        }
        if winner == established {
            candidate = nil
            return established
        }
        let strong = usable.count >= Self.strongVotes && Double(counts[winner]!) / Double(usable.count) >= Self.strongShare
        if strong || candidate == winner {
            current = winner
            candidate = nil
        } else {
            candidate = winner
        }
        return current
    }
}
