import Foundation

/// How hard to work on transcription, described to people as trade-offs, not model names.
public enum TranscriptionQuality: String, Codable, CaseIterable, Sendable {
    /// Built into macOS: nothing large to download, very fast.
    case instant
    /// Downloads once (~650 MB): accurate in every language.
    case balanced
    /// Downloads once (~1.6 GB): the uncompressed model, a bit slower.
    case best

    /// Higher is more accurate.
    var accuracy: Int {
        switch self {
        case .instant: 0
        case .balanced: 1
        case .best: 2
        }
    }

    /// What a recording is transcribed with while it runs. A slower Best model may not keep up with
    /// both sides of a call on every Mac (the old large-v3 ran a real call at 0.7x real time), so
    /// when Best uses a different model, recordings are done with Balanced first and redone at
    /// Best in the background.
    public var whileRecording: TranscriptionQuality {
        self == .best && EngineCatalog.whisperModel(for: .best) != EngineCatalog.whisperModel(for: .balanced) ? .balanced : self
    }

    /// The more accurate pass still owed after text was produced at `produced`: `wanted` if it's
    /// better than what's there, otherwise nothing.
    public static func upgrade(to wanted: TranscriptionQuality?, after produced: TranscriptionQuality) -> TranscriptionQuality? {
        guard let wanted, wanted.accuracy > produced.accuracy else { return nil }
        return wanted
    }
}

public struct TranscriptionSettings: Codable, Equatable, Sendable {
    /// ISO 639-1 codes of the languages people speak in their conversations.
    public var languages: [String]
    public var quality: TranscriptionQuality
    /// Re-transcribe with the most accurate setup while the Mac is idle.
    public var enhanceWhenIdle: Bool
    /// Names and terms to recognize (people, companies, jargon).
    public var vocabulary: [String]
    public var completedOnboarding: Bool

    public static let `default` = TranscriptionSettings(
        languages: [], quality: .balanced, enhanceWhenIdle: true, vocabulary: [], completedOnboarding: false
    )

    static let key = "transcriptionSettings"

    public static func load(from defaults: UserDefaults = .standard) -> TranscriptionSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(TranscriptionSettings.self, from: data) else { return .default }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

public struct LanguageOption: Identifiable, Hashable, Sendable {
    public var code: String
    public var name: String
    public var english: String
    public var flag: String
    public var id: String { code }

    /// Shown first in onboarding; Whisper understands ~100 more.
    public static let all: [LanguageOption] = [
        .init(code: "en", name: "English", english: "English", flag: "🇬🇧"),
        .init(code: "tr", name: "Türkçe", english: "Turkish", flag: "🇹🇷"),
        .init(code: "it", name: "Italiano", english: "Italian", flag: "🇮🇹"),
        .init(code: "de", name: "Deutsch", english: "German", flag: "🇩🇪"),
        .init(code: "es", name: "Español", english: "Spanish", flag: "🇪🇸"),
        .init(code: "fr", name: "Français", english: "French", flag: "🇫🇷"),
        .init(code: "pt", name: "Português", english: "Portuguese", flag: "🇵🇹"),
        .init(code: "nl", name: "Nederlands", english: "Dutch", flag: "🇳🇱"),
        .init(code: "ru", name: "Русский", english: "Russian", flag: "🇷🇺"),
        .init(code: "ar", name: "العربية", english: "Arabic", flag: "🇸🇦"),
        .init(code: "ja", name: "日本語", english: "Japanese", flag: "🇯🇵"),
        .init(code: "zh", name: "中文", english: "Chinese", flag: "🇨🇳"),
        .init(code: "ko", name: "한국어", english: "Korean", flag: "🇰🇷"),
    ]

    public static func named(_ code: String) -> LanguageOption? { all.first { $0.code == code } }
}

/// Which engine handles what. Kept here so product copy and routing agree.
public enum EngineCatalog {
    /// Languages macOS can transcribe on its own (SpeechAnalyzer), with the locale to use.
    public static let instantLocales: [String: String] = [
        "en": "en-US", "it": "it-IT", "de": "de-DE", "es": "es-ES", "fr": "fr-FR",
        "pt": "pt-BR", "ja": "ja-JP", "ko": "ko-KR", "zh": "zh-CN",
    ]

    /// Languages the European model (Parakeet) handles faster and more accurately than Whisper.
    static let europeanModelLanguages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv",
        "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    public static func usesEuropeanModel(for language: String) -> Bool {
        europeanModelLanguages.contains(language)
    }

    public static func unsupportedByInstant(_ languages: [String]) -> [String] {
        languages.filter { instantLocales[$0] == nil }
    }

    public static func recommendedQuality(for languages: [String]) -> TranscriptionQuality {
        !languages.isEmpty && unsupportedByInstant(languages).isEmpty ? .instant : .balanced
    }

    /// One-time download, in megabytes, for a setup (shown to people before they commit).
    public static func downloadSize(for quality: TranscriptionQuality, languages: [String]) -> Int {
        let european = languages.contains(where: usesEuropeanModel) ? 600 : 0
        switch setup(for: quality, languages: languages, appleAvailable: true) {
        case .apple: return 0
        case .whisper(let model, _): return (modelSizes[model] ?? 650) + european
        }
    }

    // MARK: - Choosing a model for the user

    /// Whisper large-v3 turbo, compressed: fast enough for live calls, complete on Turkish.
    public static let turboModel = "openai_whisper-large-v3-v20240930_turbo_632MB"
    /// The same model uncompressed (~1.6 GB). On a 23-minute Turkish call it matched the compressed
    /// one on text and gaps, wrote no garbled lines (vs 1) and varied a little less between runs,
    /// at 10.6x real time instead of 14.7x on an M4 Pro: Best's careful option.
    public static let fullTurboModel = "openai_whisper-large-v3-v20240930"
    /// Whisper large-v3, compressed. Retired: on a real Turkish call it dropped a third of the
    /// speech and gave different text on every run (see ModelEvaluationTests).
    public static let retiredModels = ["openai_whisper-large-v3_947MB"]
    static let modelSizes = [turboModel: 650, fullTurboModel: 1_600]

    /// The Whisper model behind each quality. People pick a speed, never a model: these are chosen
    /// by measuring real conversations (`ModelEvaluationTests`), not by model names.
    public static func whisperModel(for quality: TranscriptionQuality) -> String {
        switch quality {
        case .instant, .balanced: turboModel
        case .best: bestWhisperModel
        }
    }

    static let bestWhisperModel = fullTurboModel

    public enum Setup: Equatable, Sendable {
        /// The recognizer built into macOS.
        case apple
        /// Whisper, plus the European model for the languages it does better (`european`).
        case whisper(model: String, european: Bool)
    }

    /// What transcribes for this quality and these languages. Instant uses the Mac's own recognizer
    /// only when it knows every language spoken; otherwise Turkish (say) would be heard as English.
    public static func setup(for quality: TranscriptionQuality, languages: [String], appleAvailable: Bool) -> Setup {
        let european = languages.isEmpty || languages.contains(where: usesEuropeanModel)
        if quality == .instant, appleAvailable, !languages.isEmpty, unsupportedByInstant(languages).isEmpty {
            return .apple
        }
        return .whisper(model: whisperModel(for: quality), european: european)
    }
}
