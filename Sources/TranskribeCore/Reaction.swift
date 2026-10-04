import Foundation

/// A quick spoken reaction ("Esatto!", "Aynen", "Haha") shown as a tapback on the message it
/// responds to, instead of as a message of its own.
public struct Reaction: Equatable, Sendable, Identifiable {
    public var id: Segment.ID
    public var speaker: Int?
    public var kind: Kind
    public var text: String
    public var time: TimeInterval

    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case exactly, agree, ok, laugh, wow, thinking, love

        public var emoji: String {
            switch self {
            case .exactly: "💯"
            case .agree: "👍"
            case .ok: "👌"
            case .laugh: "😂"
            case .wow: "😮"
            case .thinking: "🤔"
            case .love: "❤️"
            }
        }

        /// Turkish, English and Italian, matched without accents or punctuation.
        static let lexicon: [Kind: [String]] = [
            .exactly: ["aynen", "kesinlikle", "aynen oyle", "aynen aynen", "tam olarak", "exactly", "absolutely", "precisely",
                       "totally", "esatto", "appunto", "infatti", "esattamente", "assolutamente", "proprio cosi"],
            .agree: ["evet", "evet evet", "he", "hi hi", "hihi", "dogru", "dogru dogru", "yes", "yeah", "yep", "yup", "right",
                     "true", "sure", "of course", "si", "si si", "certo", "giusto", "vero", "ovviamente", "esatto si"],
            .ok: ["tamam", "tamam tamam", "tamamdir", "peki", "olur", "anladim", "okey", "ok", "okay", "alright", "got it",
                  "i see", "fine", "va bene", "ok va bene", "d accordo", "daccordo", "capito", "ho capito", "bene", "ecco"],
            .laugh: ["haha", "hahaha", "hahahaha", "hehe", "ahaha", "ahahah", "lol"],
            .wow: ["vay", "vay be", "vay canina", "oha", "hadi ya", "gercekten mi", "sahi mi", "wow", "really", "no way", "oh wow",
                   "davvero", "ma dai", "incredibile", "caspita", "accidenti"],
            .thinking: ["hmm", "hmmm", "hm", "mm", "mmm", "hmm hmm", "bakalim", "let me think", "boh", "mah", "vediamo"],
            .love: ["super", "harika", "mukemmel", "cok guzel", "efsane", "great", "perfect", "awesome", "amazing", "love it",
                    "nice", "perfetto", "bellissimo", "fantastico", "ottimo", "grande", "che bello"],
        ]

        private static let index: [String: Kind] = {
            var map: [String: Kind] = [:]
            for kind in Kind.allCases {
                for phrase in lexicon[kind] ?? [] { map[phrase] = kind }
            }
            return map
        }()

        /// The kind of reaction `text` is, or nil if it's an actual message.
        public static func classify(_ text: String) -> Kind? {
            let normalized = TranscriptSearch.normalize(text)
                .components(separatedBy: CharacterSet.letters.union(.whitespaces).inverted).joined(separator: " ")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !normalized.isEmpty, normalized.split(separator: " ").count <= 3 else { return nil }
            if let kind = index[normalized] { return kind }
            // Doubled or tripled single words: "evet evet evet", "tamam tamam".
            let parts = Set(normalized.split(separator: " ").map(String.init))
            if parts.count == 1, let only = parts.first, let kind = index[only] { return kind }
            if normalized.hasPrefix("haha") || normalized.hasPrefix("ahah") { return .laugh }
            return nil
        }
    }
}
