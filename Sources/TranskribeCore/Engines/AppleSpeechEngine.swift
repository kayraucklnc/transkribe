import AVFoundation
import Foundation
import NaturalLanguage
import Speech

/// The speech recognizer built into macOS 26: nothing large to download (language packs are
/// small and installed by the system), very fast, private. Doesn't cover every language.
@available(macOS 26, *)
public actor AppleSpeechEngine: SpeechEngine {
    private let locales: [Locale]
    private let vocabulary: [String]
    private var lastLocale: Locale?

    public init(languages: [String], vocabulary: [String] = []) {
        let identifiers = languages.compactMap { EngineCatalog.instantLocales[$0] }
        locales = (identifiers.isEmpty ? ["en-US"] : identifiers).map(Locale.init(identifier:))
        self.vocabulary = vocabulary
    }

    public static var isAvailable: Bool { SpeechTranscriber.isAvailable }

    public func prepare(onProgress: @escaping @Sendable (TranscriptionEngine.Preparation) -> Void) async throws {
        for (index, locale) in locales.enumerated() {
            let transcriber = makeTranscriber(locale)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let base = Double(index) / Double(locales.count)
                let observation = request.progress.observe(\.fractionCompleted) { progress, _ in
                    onProgress(.downloading(base + progress.fractionCompleted / Double(self.locales.count)))
                }
                try await request.downloadAndInstall()
                observation.invalidate()
            }
        }
        onProgress(.ready)
    }

    public func transcribe(samples: [Float], onSegments: @escaping @Sendable ([RawSegment]) -> Void) async throws -> TranscriptionEngine.Output {
        guard !samples.isEmpty else { return .init(segments: [], language: nil) }
        let locale = try await chooseLocale(for: samples)
        let segments = try await recognize(samples, locale: locale).map { segment -> RawSegment in
            var segment = segment
            segment.text = VocabularyCorrector.correct(segment.text, vocabulary: vocabulary)
            segment.words = VocabularyCorrector.correct(words: segment.words, vocabulary: vocabulary)
            return segment
        }
        onSegments(segments)
        let code = locale.language.languageCode?.identifier
        let characters = segments.reduce(0) { $0 + $1.text.count }
        return .init(segments: segments, language: code, languageWeights: code.map { [$0: characters] } ?? [:])
    }

    // MARK: - Helpers

    private func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
    }

    /// With several languages, a short sample is recognized in each and the one whose text
    /// actually reads as that language wins.
    private func chooseLocale(for samples: [Float]) async throws -> Locale {
        guard locales.count > 1 else { return locales[0] }
        let probe = Array(samples.prefix(Int(AudioDecoder.sampleRate) * 20))
        var best: (locale: Locale, score: Double)?
        for locale in locales {
            let text = try await recognize(probe, locale: locale).map(\.text).joined(separator: " ")
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            let code = locale.language.languageCode?.identifier ?? ""
            let score = recognizer.languageHypotheses(withMaximum: 5)[NLLanguage(rawValue: code)] ?? 0
            if score > (best?.score ?? -1) { best = (locale, score) }
        }
        let chosen = (best?.score ?? 0) > 0.3 ? best!.locale : (lastLocale ?? locales[0])
        lastLocale = chosen
        return chosen
    }

    private func recognize(_ samples: [Float], locale: Locale) async throws -> [RawSegment] {
        let transcriber = makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        let input = try await buffer(samples, for: transcriber)
        let collector = Task { () -> [(text: String, start: TimeInterval, end: TimeInterval)] in
            var runs: [(text: String, start: TimeInterval, end: TimeInterval)] = []
            for try await result in transcriber.results {
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    runs.append((String(result.text[run.range].characters), range.start.seconds, range.end.seconds))
                }
            }
            return runs
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        continuation.yield(AnalyzerInput(buffer: input))
        continuation.finish()
        if let end = try await analyzer.analyzeSequence(stream) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return SegmentAssembly.fromWordRuns(try await collector.value)
    }

    /// 16 kHz mono floats, converted to the format the recognizer prefers.
    private func buffer(_ samples: [Float], for transcriber: SpeechTranscriber) async throws -> AVAudioPCMBuffer {
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioDecoder.sampleRate, channels: 1, interleaved: false)!
        let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count))!
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              target != source, let converter = AVAudioConverter(from: source, to: target) else { return input }
        let capacity = AVAudioFrameCount(Double(samples.count) * target.sampleRate / source.sampleRate) + 1024
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)!
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return output
    }
}
