import Foundation
import Testing
@testable import TranskribeCore

/// Compares speech models on your own recordings, through the same windowed pipeline the app uses.
///
///     TRANSKRIBE_EVAL_DIR=~/calls TRANSKRIBE_EVAL_MODELS=turbo+parakeet,turbo-full \
///       swift test --filter ModelEvaluationTests
///
/// `TRANSKRIBE_EVAL_DIR` holds conversation folders (as in the app's Library: `transcript.json` and
/// its audio) or audio files. A `<track>.reference.txt` next to a track (e.g.
/// `microphone.reference.txt`) adds word error rate. Optional: `TRANSKRIBE_EVAL_LANGUAGES`
/// (default `en,tr,it`), `TRANSKRIBE_EVAL_RUNS` (2 = also measure run-to-run stability),
/// `TRANSKRIBE_EVAL_OUT` (a JSON report). Models download on first use.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_EVAL_DIR"] != nil), .serialized)
struct ModelEvaluationTests {
    static let aliases = [
        "turbo": TranscriptionEngine.defaultModel,
        "turbo-full": "openai_whisper-large-v3-v20240930",
        "large-v3": "openai_whisper-large-v3_947MB",
    ]

    struct Track { let name: String; let url: URL; let offset: TimeInterval }
    struct Recording { let name: String; let folder: URL; let tracks: [Track] }

    struct Row: Codable {
        var recording: String, model: String
        var seconds: Double, realtime: Double
        var characters: Int, charactersPerSpeechSecond: Double
        var silentStretches: Int, silentSeconds: Double
        var garbledLines: Int
        var wordErrorRate: Double?
        var runToRunDifference: Double?
    }

    @Test func compareModels() async throws {
        let env = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: (env["TRANSKRIBE_EVAL_DIR"]! as NSString).expandingTildeInPath)
        let models = (env["TRANSKRIBE_EVAL_MODELS"] ?? "turbo+parakeet").split(separator: ",").map(String.init)
        let languages = Set((env["TRANSKRIBE_EVAL_LANGUAGES"] ?? "en,tr,it").split(separator: ",").map(String.init))
        let runs = max(1, Int(env["TRANSKRIBE_EVAL_RUNS"] ?? "1") ?? 1)
        let european = ParakeetEngine()
        var rows: [Row] = []

        for recording in try Self.recordings(in: directory) {
            let duration = try await recording.tracks.asyncMax { try await AudioDecoder.duration(of: $0.url) + $0.offset }
            let speech = try await recording.tracks.asyncSum { track in
                GapFinder.speechRegions(in: try await AudioDecoder.decode(url: track.url)).reduce(0) { $0 + $1.upperBound - $1.lowerBound }
            }
            for spec in models {
                let parts = spec.split(separator: "+").map(String.init)
                let model = Self.aliases[parts[0]] ?? parts[0]
                let engine = TranscriptionEngine(model: model, languages: languages,
                                                 european: parts.contains("parakeet") ? european : nil)
                try await engine.prepare()
                var texts: [String] = []
                var row: Row?
                for _ in 0..<runs {
                    let began = Date()
                    var segments: [RawSegment] = [], perTrack: [String: String] = [:]
                    for track in recording.tracks {
                        let result = try await TrackTranscriber(source: FileAudioSource(url: track.url), engine: engine,
                                                                diarization: nil, planner: .file).run { _ in }
                        segments += result.segments.map { TrackTranscriber.shift($0, by: track.offset) }
                        perTrack[track.name] = result.segments.map(\.text).joined(separator: " ")
                    }
                    let seconds = Date().timeIntervalSince(began)
                    texts.append(perTrack.keys.sorted().map { perTrack[$0]! }.joined(separator: " "))
                    guard row == nil else { continue }
                    let silent = TranscriptMetrics.silentStretches(segments, duration: duration)
                    let characters = segments.reduce(0) { $0 + $1.text.count }
                    let errors = recording.tracks.compactMap { track -> (Double, Int)? in
                        let file = recording.folder.appendingPathComponent("\(track.name).reference.txt")
                        guard let reference = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                        return (TranscriptMetrics.wordErrorRate(reference: reference, hypothesis: perTrack[track.name] ?? ""),
                                TranscriptMetrics.words(reference).count)
                    }
                    let words = errors.reduce(0) { $0 + $1.1 }
                    row = Row(recording: recording.name, model: spec, seconds: seconds, realtime: duration * Double(recording.tracks.count) / seconds,
                              characters: characters, charactersPerSpeechSecond: speech > 0 ? Double(characters) / speech : 0,
                              silentStretches: silent.count, silentSeconds: silent.reduce(0) { $0 + $1.upperBound - $1.lowerBound },
                              garbledLines: TranscriptMetrics.garbledLines(segments, languages: languages).count,
                              wordErrorRate: words > 0 ? errors.reduce(0) { $0 + $1.0 * Double($1.1) } / Double(words) : nil)
                }
                if texts.count > 1 { row?.runToRunDifference = TranscriptMetrics.wordErrorRate(reference: texts[0], hypothesis: texts[1]) }
                if let row {
                    rows.append(row)
                    print(Self.format(row))
                }
            }
        }
        if let out = env["TRANSKRIBE_EVAL_OUT"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(rows).write(to: URL(fileURLWithPath: out))
        }
    }

    static func format(_ row: Row) -> String {
        var text = String(format: "EVAL %@ | %@ | %.1fx real time | %d chars (%.1f per speech s) | %d silent stretches (%.0f s) | %d garbled",
                          row.recording, row.model, row.realtime, row.characters, row.charactersPerSpeechSecond,
                          row.silentStretches, row.silentSeconds, row.garbledLines)
        if let wer = row.wordErrorRate { text += String(format: " | WER %.1f%%", wer * 100) }
        if let difference = row.runToRunDifference { text += String(format: " | runs differ %.1f%%", difference * 100) }
        return text
    }

    /// Conversation folders (tracks and offsets from `transcript.json`) or loose audio files.
    static func recordings(in directory: URL) throws -> [Recording] {
        let audio = ["m4a", "wav", "mp3", "aiff", "caf"]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601 // as TranscriptStore saves it
        if let data = try? Data(contentsOf: directory.appendingPathComponent("transcript.json")),
           let transcript = try? decoder.decode(Transcript.self, from: data) {
            let tracks = transcript.tracks.map {
                Track(name: ($0.fileName as NSString).deletingPathExtension,
                      url: directory.appendingPathComponent($0.fileName), offset: $0.offset)
            }
            return [Recording(name: transcript.title, folder: directory, tracks: tracks)]
        }
        let items = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try items.flatMap { item -> [Recording] in
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return try recordings(in: item) }
            guard audio.contains(item.pathExtension.lowercased()) else { return [] }
            let name = item.deletingPathExtension().lastPathComponent
            return [Recording(name: name, folder: directory, tracks: [Track(name: name, url: item, offset: 0)])]
        }
    }
}

private extension Array {
    func asyncMax(_ value: (Element) async throws -> Double) async rethrows -> Double {
        var best = 0.0
        for element in self { best = Swift.max(best, try await value(element)) }
        return best
    }

    func asyncSum(_ value: (Element) async throws -> Double) async rethrows -> Double {
        var total = 0.0
        for element in self { total += try await value(element) }
        return total
    }
}
