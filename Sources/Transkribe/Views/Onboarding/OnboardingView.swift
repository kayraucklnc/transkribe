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
        case welcome, languages, quality, words, permissions, ready
    }

    var body: some View {
        ZStack {
            AmbientBackground()
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
        VStack(spacing: 26) {
            ZStack {
                Circle()
                    .fill(Theme.record.opacity(0.35))
                    .frame(width: 150, height: 150)
                    .blur(radius: 40)
                Image(systemName: "waveform")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 120)
                    .background(
                        LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.4), Color(red: 0.84, green: 0.12, blue: 0.36)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                    )
                    .shadow(color: Theme.record.opacity(0.4), radius: 20, y: 10)
            }
            VStack(spacing: 12) {
                Text("Every conversation,\nwritten down.")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Record a call or drop any recording. Transkribe turns it into a readable chat you can search, replay and ask about — privately, on your Mac.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            PrimaryButton(title: "Get Started") { go(to: .languages) }
                .padding(.top, 8)
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
            if step == .words || step == .permissions {
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
        case .permissions:
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
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
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
                .background(Theme.myBubble, in: Capsule())
                .shadow(color: Color.accentColor.opacity(isHovered ? 0.5 : 0.3), radius: isHovered ? 16 : 10, y: 4)
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
                    .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.primary.opacity(0.15))
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
            Heading(title: "Two quick permissions", subtitle: "So Transkribe can hear your conversations. You can also do this later.")
            PermissionCard(symbol: "mic.fill", title: "Your microphone", detail: "To record what you and people in the room say.",
                           granted: microphone) {
                Task {
                    try? await RecordingSession.requestPermissions(for: .microphone)
                    microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                }
            }
            PermissionCard(symbol: "speaker.wave.2.fill", title: "Sound from calls and apps",
                           detail: "To capture the other side of Zoom, Meet or FaceTime calls. Your screen is never recorded.",
                           granted: systemAudio) {
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
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Theme.myBubble, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
        .background(Theme.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.spring(response: 0.35), value: granted)
    }
}

private struct ReadyStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: [.accentColor, .purple, .pink, .accentColor], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6), value: progress)
                Image(systemName: isDone ? "checkmark" : "arrow.down")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 130, height: 130)
            Text(isDone ? "You're all set" : "Getting things ready")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(isDone
                 ? "Press the red button to record, or drop any recording into the window."
                 : "This happens once. You can start using Transkribe now — anything you record waits until it's ready.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
    }

    private var progress: Double {
        switch model.modelPreparation {
        case .downloading(let fraction)?: max(0.04, fraction * 0.9)
        case .loading?: 0.95
        case .ready?: 1
        case nil: 0.04
        }
    }

    private var isDone: Bool {
        if case .ready? = model.modelPreparation { return true }
        return false
    }
}
