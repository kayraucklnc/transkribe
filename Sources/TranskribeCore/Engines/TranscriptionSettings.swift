import Foundation

/// How hard to work on transcription, described to people as trade-offs, not model names.
public enum TranscriptionQuality: String, Codable, CaseIterable, Sendable {
    /// Built into macOS: nothing large to download, very fast.
    case instant
    /// Downloads once (~650 MB): accurate in every language.
    case balanced
    /// Downloads once (~1 GB): most accurate, a bit slower.
    case best
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
        switch quality {
        case .instant: return 0
        case .balanced: return 650 + european
        case .best: return 1_000 + european
        }
    }
}
