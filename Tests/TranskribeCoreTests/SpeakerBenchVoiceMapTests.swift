import Foundation
import Testing
@testable import TranskribeCore

/// Exploration: one voiceprint per (conversation, track, speaker label) in a Library, and how alike
/// they are, to pick clean voices for the speaker separation benchmark.
///
///     TRANSKRIBE_VOICEMAP_DIR=~/Library/Application\ Support/Transkribe/Library swift test --filter SpeakerBenchVoiceMapTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TRANSKRIBE_VOICEMAP_DIR"] != nil))
struct SpeakerBenchVoiceMapTests {
    @Test func voiceMap() async throws {
        let env = ProcessInfo.processInfo.environment
        let library = URL(fileURLWithPath: (env["TRANSKRIBE_VOICEMAP_DIR"]! as NSString).expandingTildeInPath)
        let engine = VoiceprintEngine()
        var voices: [(name: String, print: [Float], seconds: Double)] = []
        let store = TranscriptStore(rootDirectory: library)
        for transcript in try store.loadAll().sorted(by: { store.directory(for: $0).path < store.directory(for: $1).path }) {
            let folder = store.directory(for: transcript)
            let withCall = transcript.tracks.contains { $0.source == .system }
            for track in transcript.tracks {
                let samples = try await AudioDecoder.decode(url: store.audioURL(for: transcript, track: track))
                let labels = Set(transcript.segments.compactMap(\.speaker)).sorted()
                for label in labels {
                    if withCall, SpeakerID.isOnMicrophone(label) != (track.source == .microphone) { continue }
                    let ranges = VoiceClips.ranges(for: label, in: transcript.segments)
                    let clips = ranges.map { range in
                        Array(samples[max(0, Int(range.start * 16000))..<min(samples.count, Int(range.end * 16000))])
                    }
                    guard let print = try await engine.voiceprint(clips: clips) else { continue }
                    let seconds = ranges.reduce(0) { $0 + $1.end - $1.start }
                    voices.append(("\(folder.lastPathComponent.prefix(8))/\(track.fileName.prefix(3))/\(label)", print, seconds))
                }
            }
        }
        var lines = ["voice\tclipSeconds\t" + voices.map(\.name).joined(separator: "\t")]
        for voice in voices {
            lines.append("\(voice.name)\t\(Int(voice.seconds))\t" + voices.map { String(format: "%.2f", Voiceprint.similarity(voice.print, $0.print)) }.joined(separator: "\t"))
        }
        let out = env["TRANSKRIBE_VOICEMAP_OUT"].map { URL(fileURLWithPath: $0) }
        try out.map { try lines.joined(separator: "\n").write(to: $0, atomically: true, encoding: .utf8) }
        print(lines.joined(separator: "\n"))
    }
}
