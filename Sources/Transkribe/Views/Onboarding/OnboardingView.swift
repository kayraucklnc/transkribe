import AVFoundation
import SwiftUI
import TranskribeCore

/// First run: a few friendly questions, no jargon, and everything is ready at the end.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = Step.welcome
    @State private var draft = TranscriptionSettings.default
    @State private var forward = true

    enum Step: Int, CaseIterable {
        case welcome, languages, quality, words, permissions, dictation, ready
    }

    var body: some View {
        ZStack {
            StageBackdrop()
            VStack(spacing: 0) {
                if step != .welcome {
                    StepDots(step: step)
                        .padding(.top, 40)
                        .transition(.opacity)
                }
                Spacer(minLength: 20)
                Group {
                    switch step {
                    case .welcome: welcome
                    case .languages: languages
                    case .quality: quality
                    case .words: words
                    case .permissions: PermissionsStep()
                    case .dictation: DictationStep()
                    case .ready: ReadyStep()
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 40)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                ))
                Spacer(minLength: 20)
                if step != .welcome { controls.padding(.bottom, 40) }
            }
        }
        .onAppear {
            draft = model.settings
            if draft.vocabulary.isEmpty, let first = NSFullUserName().split(separator: " ").first {
                draft.vocabulary = [String(first)]
            }
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 30) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: Theme.record.opacity(0.45), radius: 30, y: 12)
                .modifier(Rise(delay: 0))
            VStack(spacing: 14) {
                Text("Every word, kept.")
                    .font(.system(size: 54, weight: .bold))
                    .tracking(-1.4)
                Text("Transkribe turns your calls, meetings and voice notes into chats you can read, search and ask about. Everything stays on this Mac.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            .modifier(Rise(delay: 0.08))
            HStack(spacing: 14) {
                Pillar(symbol: "record.circle", tint: Theme.record, title: "Record", detail: "Calls and meetings")
                Pillar(symbol: "arrow.down.doc", tint: .blue, title: "Import", detail: "Any audio or video file")
                Pillar(symbol: "mic", tint: .gray, title: "Dictate", detail: "Talk, and it types for you")
            }
            .modifier(Rise(delay: 0.16))
            PrimaryButton(title: "Get Started") { go(to: .languages) }
                .padding(.top, 6)
                .modifier(Rise(delay: 0.24))
        }
    }

    private var languages: some View {
        VStack(alignment: .leading, spacing: 22) {
            Heading(title: "Which languages do you speak?",
                    subtitle: "Pick every language your conversations are in. You can change this anytime.")
            LanguagePicker(selection: $draft.languages)
        }
    }

    private var quality: some View {
        VStack(alignment: .leading, spacing: 20) {
            Heading(title: "How should Transkribe listen?", subtitle: "You can switch later in Settings.")
            QualityPicker(quality: $draft.quality, languages: draft.languages)
            Toggle(isOn: $draft.enhanceWhenIdle) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make transcripts even better while you're away").font(.callout.weight(.semibold))
                    Text(draft.quality == .best
                         ? "Already at the best quality."
                         : "When your Mac is idle and plugged in, Transkribe quietly redoes recent conversations at the highest quality\(draft.quality == .best ? "" : " (downloads about 1 GB once)").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(draft.quality == .best)
            .padding(14)
            .background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 22) {
            Heading(title: "Any names or words we should know?",
                    subtitle: "Your name, your company, clients, products, jargon. Transkribe will spell them right.")
            VocabularyEditor(words: $draft.vocabulary)
        }
    }

    // MARK: - Navigation

    private var controls: some View {
        HStack {
            if step.rawValue > Step.languages.rawValue {
                Button("Back") { go(to: Step(rawValue: step.rawValue - 1)!) }
                    .buttonStyle(.borderless)
                    .font(.body.weight(.medium))
            }
            Spacer()
            if step == .words || step == .permissions || step == .dictation {
                Button("Skip") { advance() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
            }
            PrimaryButton(title: step == .ready ? "Start Using Transkribe" : "Continue", action: advance)
                .disabled(step == .languages && draft.languages.isEmpty)
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 40)
    }

    private func advance() {
        switch step {
        case .languages:
            draft.quality = EngineCatalog.recommendedQuality(for: draft.languages)
            go(to: .quality)
        case .dictation:
            // Settle the setup now so downloads start while the last screen shows.
            var settings = draft
            settings.completedOnboarding = false
            model.settings = settings
            model.preloadModel()
            go(to: .ready)
        case .ready:
            var settings = draft
            settings.completedOnboarding = true
            withAnimation(.easeInOut(duration: 0.5)) { model.settings = settings }
            model.finishOnboarding()
        default:
            go(to: Step(rawValue: step.rawValue + 1)!)
        }
    }

    private func go(to next: Step) {
        forward = next.rawValue > step.rawValue
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = next }
    }
}

private struct Heading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 32, weight: .bold)).tracking(-0.6)
            Text(subtitle).font(.system(size: 16)).foregroundStyle(.secondary)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Theme.record, in: Capsule())
                .shadow(color: Theme.record.opacity(isHovered ? 0.55 : 0.3), radius: isHovered ? 18 : 10, y: 4)
                .scaleEffect(isHovered ? 1.03 : 1)
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .onHover { hovering in withAnimation(.spring(response: 0.3)) { isHovered = hovering } }
    }
}

private struct StepDots: View {
    let step: OnboardingView.Step

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingView.Step.allCases.dropFirst(), id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.record : Color.primary.opacity(0.15))
                    .frame(width: item == step ? 26 : 8, height: 8)
                    .animation(.spring(response: 0.4), value: step)
            }
        }
    }
}

private struct PermissionsStep: View {
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var systemAudio = CGPreflightScreenCaptureAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Heading(title: "Let Transkribe listen", subtitle: "macOS asks once for each. You can also do this later in System Settings.")
            PermissionCard(symbol: "mic.fill", title: "Your microphone", detail: "To record what you and people in the room say.",
                           granted: microphone) {
                Task {
                    try? await RecordingSession.requestPermissions(for: .microphone)
                    microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                }
            }
            PermissionCard(symbol: "speaker.wave.2.fill", title: "Sound from calls and apps",
                           detail: "To capture the other side of Zoom, Meet or FaceTime calls. Your screen is never recorded.",
                           granted: systemAudio, tint: .blue) {
                _ = CGRequestScreenCaptureAccess()
                systemAudio = CGPreflightScreenCaptureAccess()
            }
        }
    }
}

private struct PermissionCard: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    var tint: Color = Theme.record
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(tint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.semibold))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Allow", action: onAllow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Stage.hairline, lineWidth: 1))
        .animation(.spring(response: 0.35), value: granted)
    }
}

private struct ReadyStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.record, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6), value: progress)
                Image(systemName: isDone ? "checkmark" : "waveform")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(isDone ? Color.green : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 124, height: 124)
            Text(isDone ? "You're all set" : title)
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.6)
            Text(isDone
                 ? "Press the red button to record, drop any recording into the window, or use your shortcut to dictate."
                 : detail)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            if !isDone {
                Text("You can start now. Anything you record waits until it's ready.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        switch model.modelPreparation {
        case .downloading?: "Downloading the speech model"
        case .loading(true)?: "Tuning it for your Mac"
        default: "Getting things ready"
        }
    }

    private var detail: String {
        switch model.modelPreparation {
        case .downloading(let fraction)?:
            "\(fraction.formatted(.percent.precision(.fractionLength(0)))) · It runs entirely on this Mac, so it's downloaded once."
        case .loading(true)?:
            "macOS optimizes the model for your Mac's chip. This takes a few minutes, only the first time."
        default:
            "Almost there."
        }
    }

    private var progress: Double {
        switch model.modelPreparation {
        case .downloading(let fraction)?: max(0.04, fraction * 0.85)
        case .loading?: 0.92
        case .ready?: 1
        case nil: 0.04
        }
    }

    private var isDone: Bool {
        if case .ready? = model.modelPreparation { return true }
        return false
    }
}

/// Teaches the shortcut and asks for Accessibility so dictated words can be typed into other apps.
private struct DictationStep: View {
    @Environment(DictationController.self) private var dictation
    @State private var isTrusted = TextInserter.isTrusted

    var body: some View {
        @Bindable var dictation = dictation
        VStack(alignment: .leading, spacing: 22) {
            Heading(title: "Talk instead of typing",
                    subtitle: "In any app, press your shortcut and speak. Let go (or press Return) and your words appear where the cursor is.")
            HStack(spacing: 16) {
                Image(systemName: "keyboard")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.gray, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your shortcut").font(.headline)
                    Text("Click to change it, then press the keys you want.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                ShortcutRecorder(shortcut: $dictation.shortcut, onBegin: dictation.suspendShortcut, onEnd: dictation.installShortcut)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Stage.hairline, lineWidth: 1))
            PermissionCard(symbol: "character.cursor.ibeam", title: "Type for you",
                           detail: "Lets dictation put words into other apps. Without it, your words are copied and you press ⌘V.",
                           granted: isTrusted, tint: .purple) {
                TextInserter.requestTrust()
            }
        }
        .task {
            // Accessibility is granted in System Settings; notice when the user comes back.
            while !Task.isCancelled {
                isTrusted = TextInserter.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// One of the three things Transkribe does, on the welcome screen.
private struct Pillar: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 150)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Stage.hairline, lineWidth: 1))
    }
}

/// Fades and lifts content in when it first appears.
private struct Rise: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}
