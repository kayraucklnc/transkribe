import SwiftUI
import TranskribeCore

/// Flag chips; tap to toggle. Used in onboarding and Settings.
struct LanguagePicker: View {
    @Binding var selection: [String]

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(LanguageOption.all) { option in
                let selected = selection.contains(option.code)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if selected { selection.removeAll { $0 == option.code } } else { selection.append(option.code) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(option.flag).font(.title3)
                        Text(option.name).font(.body.weight(selected ? .semibold : .regular))
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05), in: Capsule())
                    .overlay(Capsule().stroke(selected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
                    .scaleEffect(selected ? 1.03 : 1)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Three ways to listen, described by what they mean for the person, not by model names.
struct QualityPicker: View {
    @Binding var quality: TranscriptionQuality
    let languages: [String]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(TranscriptionQuality.allCases, id: \.self) { option in
                QualityCard(option: option, isSelected: quality == option, languages: languages,
                            isRecommended: EngineCatalog.recommendedQuality(for: languages) == option) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { quality = option }
                }
            }
        }
    }
}

private struct QualityCard: View {
    let option: TranscriptionQuality
    let isSelected: Bool
    let languages: [String]
    let isRecommended: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? AnyShapeStyle(Theme.myBubble) : AnyShapeStyle(Color.accentColor.opacity(0.12)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(.headline, design: .rounded))
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.green.gradient, in: Capsule())
                        }
                    }
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                    if let note {
                        Label(note, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(16)
            .background(Theme.card.opacity(isHovered || isSelected ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(option == .instant && !instantAvailable)
        .opacity(option == .instant && !instantAvailable ? 0.5 : 1)
    }

    private var instantAvailable: Bool {
        if #available(macOS 26, *) { return AppleSpeechEngine.isAvailable }
        return false
    }

    private var symbol: String {
        switch option {
        case .instant: "bolt.fill"
        case .balanced: "dial.medium.fill"
        case .best: "sparkles"
        }
    }

    private var title: String {
        switch option {
        case .instant: "Instant"
        case .balanced: "Balanced"
        case .best: "Best quality"
        }
    }

    private var detail: String {
        let size = EngineCatalog.downloadSize(for: option, languages: languages)
        let download = size >= 1_000 ? String(format: "about %.1f GB", Double(size) / 1_000) : "about \(size) MB"
        switch option {
        case .instant: return "Ready right away — built into your Mac, nothing big to download. Very fast."
        case .balanced: return "Accurate in every language. One-time download, \(download)."
        case .best: return "The most accurate. One-time download, \(download). A little slower."
        }
    }

    private var note: String? {
        guard option == .instant else { return nil }
        guard instantAvailable else { return "Needs macOS 26 or later" }
        let missing = EngineCatalog.unsupportedByInstant(languages).compactMap { LanguageOption.named($0)?.name }
        guard !missing.isEmpty else { return nil }
        return "Doesn't understand \(ListFormatter.localizedString(byJoining: missing)) yet"
    }
}

/// Names and terms to recognize, as removable chips.
struct VocabularyEditor: View {
    @Binding var words: [String]
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                TextField("Add a name or word, then press Return", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !words.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(words, id: \.self) { word in
                        HStack(spacing: 6) {
                            Text(word).font(.callout.weight(.medium))
                            Button {
                                withAnimation(.spring(response: 0.3)) { words.removeAll { $0 == word } }
                            } label: {
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }

    private func add() {
        let word = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !words.contains(word) else { draft = ""; return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { words.append(word) }
        draft = ""
        focused = true
    }
}
