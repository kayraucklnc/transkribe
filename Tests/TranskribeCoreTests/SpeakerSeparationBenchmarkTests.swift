import FluidAudio
import Foundation
import Testing
@testable import TranskribeCore

/// How well the call side's voices are told apart, on calls stitched together from real people
/// in your own Library, so the right answer is known.
///
///     TRANSKRIBE_SPEAKER_BENCH=bench.json swift test --filter SpeakerSeparationBenchmarkTests
///
/// `bench.json`: `{"library": "~/Library/Application Support/Transkribe/Library",
/// "voices": [{"conversation": "1F67A9BA", "track": "system", "speaker": 1}, …],
/// "people": [2, 4, 8], "minutes": 6, "methods": ["current", "voices"]}`. Methods: `current` (the
/// speaker model alone, as before voice separation), `voices` (what the app does now), threshold
/// and smoothing variants of it, `lseend-all` and `offline` (FluidAudio's pyannote pipeline). Each voice must be a
/// different person (check with `SpeakerBenchVoiceMapTests`). Optional `out`: a JSON report path.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_SPEAKER_BENCH"] != nil), .serialized)
struct SpeakerSeparationBenchmarkTests {
    struct Config: Decodable {
        struct Voice: Decodable { let conversation: String; let track: String; let speaker: Int }
        let library: String
        let voices: [Voice]
        let people: [Int]
        let minutes: Double?
        let methods: [String]?
        let seeds: [UInt64]?
        let out: String?
    }

    struct Row: Codable {
        var method: String, people: Int, seed: UInt64
        var der: Double, confusion: Double, miss: Double, falseAlarm: Double
        var found: Int, seconds: Double
        /// Share of words credited to the right person (what the chat shows).
        var wordAccuracy: Double
    }

    /// A stitched call: audio and who really spoke when.
    struct Call { let samples: [Float]; let truth: [SpeakerTurn]; let words: [SpeakerTurn] }

    @Test func compareMethods() async throws {
        let path = ProcessInfo.processInfo.environment["TRANSKRIBE_SPEAKER_BENCH"]!
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let pools = try await Self.pools(config)
        let methods = config.methods ?? Self.methods.keys.sorted()
        var rows: [Row] = []
        for people in config.people {
            for seed in config.seeds ?? [1, 2] {
                let call = Self.stitch(Array(pools.prefix(people)), minutes: config.minutes ?? 6, seed: seed)
                for method in methods {
                    let began = Date()
                    let turns = try await Self.methods[method]!(call.samples)
                    let result = DiarizationDER.compute(ref: Self.der(call.truth), hyp: Self.der(turns), collar: 0.25)
                    let speech = max(result.totalRefSpeech, 1)
                    let credited = call.words.filter { word in
                        SpeakerAssigner.speaker(from: word.start, to: word.end, in: turns)
                            .flatMap { result.mapping["\($0)"] } == "\(word.speaker)"
                    }
                    let row = Row(method: method, people: people, seed: seed, der: result.der, confusion: result.confusion / speech,
                                  miss: result.miss / speech, falseAlarm: result.falseAlarm / speech,
                                  found: Set(turns.map(\.speaker)).count, seconds: Date().timeIntervalSince(began),
                                  wordAccuracy: Double(credited.count) / Double(max(1, call.words.count)))
                    rows.append(row)
                    print(String(format: "%-14@ people=%2d seed=%llu  words=%5.1f%%  DER=%5.1f%% (conf %4.1f miss %4.1f fa %4.1f)  found=%2d  %.1fs",
                                 method as NSString, people, seed, row.wordAccuracy * 100, row.der * 100, row.confusion * 100,
                                 row.miss * 100, row.falseAlarm * 100, row.found, row.seconds))
                    if ProcessInfo.processInfo.environment["TRANSKRIBE_SPEAKER_BENCH_DETAIL"] != nil {
                        print(Self.breakdown(turns: turns, words: call.words))
                    }
                }
            }
        }
        if let out = config.out {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(rows).write(to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath))
        }
    }

    /// A real conversation's call side relabeled both ways, line by line, to read who said what.
    /// `TRANSKRIBE_SPEAKER_REAL=<conversation id prefix>` with `library` from the config.
    @Test func realCall() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let prefix = env["TRANSKRIBE_SPEAKER_REAL"] else { return }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: env["TRANSKRIBE_SPEAKER_BENCH"]!)))
        let store = TranscriptStore(rootDirectory: URL(fileURLWithPath: (config.library as NSString).expandingTildeInPath))
        let transcript = try #require(try store.loadAll().first { $0.id.uuidString.hasPrefix(prefix) })
        let track = try #require(transcript.tracks.first { $0.source != .microphone })
        let samples = try await AudioDecoder.decode(url: store.audioURL(for: transcript, track: track))
        let lines = transcript.segments.filter { !(transcript.tracks.count > 1 && SpeakerID.isOnMicrophone($0.speaker)) }
            .map { RawSegment(start: $0.start - track.offset, end: $0.end - track.offset, text: $0.text, words: $0.words.map {
                Word(start: $0.start - track.offset, end: $0.end - track.offset, text: $0.text) }) }
        let stream = try await DiarizationEngine().makeStream()
        try stream.append(samples)
        try stream.finish()
        let read: @Sendable (TimeInterval, TimeInterval) async throws -> [Float] = { start, end in
            Array(samples[max(0, Int(start * 16000))..<min(samples.count, Int(end * 16000))])
        }
        let engine = VoiceprintEngine()
        var variants = [("current", stream.turns())]
        for (name, smoothing) in [("none", VoiceSeparator.Smoothing.none), ("std", .standard)] {
            variants.append((name, try await engine.separateVoices(turns: stream.rawTurns(), smoothing: smoothing, read: read)))
        }
        for (name, turns) in variants {
            let assigned = SpeakerAssigner.assign(lines, turns: turns)
            var talk: [Int: Double] = [:]
            for line in assigned { for word in line.words { talk[line.speaker ?? 0, default: 0] += word.end - word.start } }
            print("=== \(name): " + talk.sorted { $0.value > $1.value }.map { String(format: "v%d %.0fs", $0.key, $0.value) }.joined(separator: ", "))
            if env["TRANSKRIBE_SPEAKER_REAL_LINES"] != nil {
                for line in assigned {
                    print(String(format: "%7.1f [%@] %@", line.start, line.speaker.map(String.init) ?? "-", String(line.text.prefix(120))))
                }
            }
        }
    }

    /// How alike two windows of the same person are, against two different people, by window length.
    @Test func embeddingSeparation() async throws {
        let path = ProcessInfo.processInfo.environment["TRANSKRIBE_SPEAKER_BENCH"]!
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let pools = try await Self.pools(config)
        let manager = try await Self.embedder()
        let camPlus = try await CampPlusEmbedder.load()
        for model in ["wespeaker", "campplus"] {
        for length in [1.0, 1.5, 2.0, 3.0, 5.0] {
            var prints: [(person: Int, print: [Float])] = []
            for (person, pool) in pools.enumerated() {
                for clip in pool.prefix(25) where Double(clip.samples.count) >= length * 16000 {
                    let window = Array(clip.samples.prefix(Int(length * 16000)))
                    if model == "campplus" {
                        prints.append((person, try await camPlus.embed(audio: window)))
                    } else {
                        let embedding = try manager.extractSpeakerEmbedding(from: window)
                        if manager.validateEmbedding(embedding) { prints.append((person, Voiceprint.normalized(embedding))) }
                    }
                }
            }
            var same: [Float] = [], different: [Float] = []
            for i in prints.indices { for j in prints.indices where j > i {
                let score = Voiceprint.similarity(prints[i].print, prints[j].print)
                if prints[i].person == prints[j].person { same.append(score) } else { different.append(score) }
            } }
            func q(_ values: [Float], _ p: Double) -> Float { let s = values.sorted(); return s.isEmpty ? .nan : s[min(s.count - 1, Int(Double(s.count) * p))] }
            let eer = Self.equalErrorRate(same: same, different: different)
            print(String(format: "EER %4.1f%%  %@ window %.1fs  n=%3d  same p10/p50/p90 %.2f %.2f %.2f   different p50/p90/p99 %.2f %.2f %.2f",
                         eer * 100, model as NSString, length, prints.count, q(same, 0.1), q(same, 0.5), q(same, 0.9), q(different, 0.5), q(different, 0.9), q(different, 0.99)))
        }
        }
    }

    /// Where wrongly rejecting the same person is as common as wrongly accepting a different one.
    static func equalErrorRate(same: [Float], different: [Float]) -> Double {
        let thresholds = Set(same + different).sorted()
        var best = 1.0
        for threshold in thresholds {
            let rejected = Double(same.filter { $0 < threshold }.count) / Double(max(1, same.count))
            let accepted = Double(different.filter { $0 >= threshold }.count) / Double(max(1, different.count))
            best = min(best, max(rejected, accepted))
        }
        return best
    }

    static func embedder() async throws -> DiarizerManager {
        let directory = TranscriptionEngine.defaultModelsDirectory.appendingPathComponent("FluidAudio", isDirectory: true)
        let manager = DiarizerManager()
        manager.initialize(models: try await DiarizerModels.downloadIfNeeded(to: directory))
        return manager
    }

    // MARK: - Methods

    static func separated(threshold: Float, smoothing: VoiceSeparator.Smoothing = .standard) -> @Sendable ([Float]) async throws -> [SpeakerTurn] {
        { samples in
            let stream = try await DiarizationEngine().makeStream()
            try stream.append(samples)
            try stream.finish()
            return try await VoiceprintEngine().separateVoices(turns: stream.rawTurns(), threshold: threshold, smoothing: smoothing) { start, end in
                Array(samples[max(0, Int(start * 16000))..<min(samples.count, Int(end * 16000))])
            }
        }
    }

    static let methods: [String: @Sendable ([Float]) async throws -> [SpeakerTurn]] = [
        "voices": separated(threshold: VoiceSeparator.defaultThreshold),
        "voices-0.20": separated(threshold: 0.20),
        "voices-0.30": separated(threshold: 0.30),
        "voices-unsmoothed": separated(threshold: VoiceSeparator.defaultThreshold, smoothing: .none),
        "current": { try await DiarizationEngine().turns(samples: $0) },
        "lseend-all": { samples in
            let stream = try await DiarizationEngine().makeStream()
            try stream.append(samples)
            try stream.finish()
            return stream.rawTurns()
        },
        "offline": { samples in
            let manager = OfflineDiarizerManager(config: .default)
            try await manager.prepareModels()
            let result = try await manager.process(audio: samples)
            let ids = Dictionary(uniqueKeysWithValues: Set(result.segments.map(\.speakerId)).sorted().enumerated().map { ($1, $0 + 1) })
            return result.segments.map {
                SpeakerTurn(start: TimeInterval($0.startTimeSeconds), end: TimeInterval($0.endTimeSeconds), speaker: ids[$0.speakerId]!)
            }
        },
    ]

    // MARK: - Building calls

    /// A stretch of one voice talking alone, and where in it the words are (from the transcript).
    struct Clip { let samples: [Float]; let speech: [Range<TimeInterval>] }

    /// Each voice's stretches of talking alone, 1–12 s long.
    static func pools(_ config: Config) async throws -> [[Clip]] {
        let store = TranscriptStore(rootDirectory: URL(fileURLWithPath: (config.library as NSString).expandingTildeInPath))
        let transcripts = try store.loadAll()
        var pools: [[Clip]] = []
        for voice in config.voices {
            let transcript = try #require(transcripts.first { $0.id.uuidString.hasPrefix(voice.conversation) })
            let track = try #require(transcript.tracks.first { ($0.source?.rawValue ?? "file") == voice.track } ?? transcript.tracks.first)
            let samples = try await AudioDecoder.decode(url: store.audioURL(for: transcript, track: track))
            let others = transcript.segments.filter { $0.speaker != voice.speaker }
            var pool: [Clip] = []
            for segment in transcript.segments where segment.speaker == voice.speaker && !segment.words.isEmpty {
                let start = segment.start - track.offset, end = segment.end - track.offset
                guard !others.contains(where: { $0.start - track.offset < end && start < $0.end - track.offset }) else { continue }
                var from = start
                while end - from >= 1 {
                    let to = min(end, from + 12)
                    let range = max(0, Int(from * 16000))..<min(samples.count, Int(to * 16000))
                    let speech = segment.words.map { ($0.start - track.offset)..<($0.end - track.offset) }
                        .compactMap { word -> Range<TimeInterval>? in
                            let clipped = max(word.lowerBound, from)..<max(max(word.lowerBound, from), min(word.upperBound, to))
                            return clipped.isEmpty ? nil : (clipped.lowerBound - from)..<(clipped.upperBound - from)
                        }
                    if range.count >= 16000, !speech.isEmpty { pool.append(Clip(samples: Array(samples[range]), speech: speech)) }
                    from = to
                }
            }
            #expect(!pool.isEmpty, "no clean speech for \(voice.conversation)/\(voice.speaker)")
            pools.append(pool)
        }
        return pools
    }

    /// Turns drawn by talk share (the first voice talks most, the last least, like a real
    /// meeting), short gaps between them, never the same voice twice in a row.
    static func stitch(_ pools: [[Clip]], minutes: Double, seed: UInt64) -> Call {
        var random = SeededRandom(seed: seed)
        let weights = pools.indices.map { 1 / pow(Double($0 + 1), 0.8) }
        var next = Array(repeating: 0, count: pools.count)
        var samples: [Float] = [], truth: [SpeakerTurn] = [], words: [SpeakerTurn] = []
        var previous: Int?
        while Double(samples.count) < minutes * 60 * 16000 {
            let choices = pools.indices.filter { $0 != previous || pools.count == 1 }
            let total = choices.reduce(0) { $0 + weights[$1] }
            var pick = Double.random(in: 0..<total, using: &random)
            let speaker = choices.first { pick -= weights[$0]; return pick < 0 } ?? choices.last!
            let clip = pools[speaker][next[speaker] % pools[speaker].count]
            next[speaker] += 1
            samples += Array(repeating: 0, count: Int(Double.random(in: 0.15...0.7, using: &random) * 16000))
            let start = Double(samples.count) / 16000
            samples += clip.samples
            // Words closer than 0.3 s count as one stretch of talking.
            for word in clip.speech {
                words.append(SpeakerTurn(start: start + word.lowerBound, end: start + word.upperBound, speaker: speaker + 1))
                if let last = truth.last, last.speaker == speaker + 1, start + word.lowerBound - last.end < 0.3 {
                    truth[truth.count - 1].end = max(last.end, start + word.upperBound)
                } else {
                    truth.append(SpeakerTurn(start: start + word.lowerBound, end: start + word.upperBound, speaker: speaker + 1))
                }
            }
            previous = speaker
        }
        return Call(samples: samples, truth: truth, words: words)
    }

    /// Per found voice: seconds of each real person's words it got.
    static func breakdown(turns: [SpeakerTurn], words: [SpeakerTurn]) -> String {
        var table: [Int: [Int: Double]] = [:]
        for word in words {
            let found = SpeakerAssigner.speaker(from: word.start, to: word.end, in: turns) ?? 0
            table[found, default: [:]][word.speaker, default: 0] += word.end - word.start
        }
        return table.keys.sorted().map { found in
            "    voice \(found): " + table[found]!.sorted { $0.value > $1.value }
                .map { String(format: "p%d %.0fs", $0.key, $0.value) }.joined(separator: ", ")
        }.joined(separator: "\n")
    }

    static func der(_ turns: [SpeakerTurn]) -> [DERSpeakerSegment] {
        turns.map { DERSpeakerSegment(speaker: "\($0.speaker)", start: $0.start, end: $0.end) }
    }
}

/// Reproducible calls from a seed (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
