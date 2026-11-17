import Foundation

/// Something that turns 16 kHz mono audio into timed text: Whisper, the built-in macOS
/// recognizer, or a combination that routes by language.
public protocol SpeechEngine: AnyObject, Sendable {
    /// Downloads (first time only) and loads whatever the engine needs.
    func prepare(onProgress: @escaping @Sendable (TranscriptionEngine.Preparation) -> Void) async throws
    func transcribe(samples: [Float], onSegments: @escaping @Sendable ([RawSegment]) -> Void) async throws -> TranscriptionEngine.Output
    /// Same, in a language already known from the audio around it. Short clips (a retried gap)
    /// are too short to tell Turkish from English reliably.
    func transcribe(samples: [Float], language: String?,
                    onSegments: @escaping @Sendable ([RawSegment]) -> Void) async throws -> TranscriptionEngine.Output
}

public extension SpeechEngine {
    func transcribe(samples: [Float], language: String?,
                    onSegments: @escaping @Sendable ([RawSegment]) -> Void) async throws -> TranscriptionEngine.Output {
        try await transcribe(samples: samples, onSegments: onSegments)
    }
}

extension TranscriptionEngine: SpeechEngine {}

/// Whisper output often ends with one of these on silence or music; they were never said.
public enum Hallucinations {
    static let phrases: Set<String> = [
        "altyazi mk", "altyazi m k", "abone olmayi unutmayin", "izlediginiz icin tesekkurler",
        "thank you", "thanks for watching", "thank you for watching", "subtitles by the amaraorg community",
        "sottotitoli creati dalla comunita amaraorg", "sottotitoli a cura di qtss", "grazie per la visione",
    ]

    public static func isHallucination(_ text: String) -> Bool {
        let key = TranscriptSearch.normalize(text)
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return phrases.contains(key)
    }
}
