import SwiftUI
import TranskribeCore

/// The black island by the notch. Its size comes from `NotchGeometry` so the window and the
/// shape agree; SwiftUI only animates between sizes.
struct NotchHUDView: View {
    let hud: NotchHUD
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let mode = hud.mode
        let geometry = hud.geometry
        let size = geometry.size(for: mode)
        VStack(spacing: 0) {
            topRow(geometry: geometry)
                .frame(height: geometry.topHeight)
            if mode.showsCard {
                card(mode)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(IslandShape(bottomRadius: mode.showsCard ? 22 : (geometry.hasNotch ? 10 : geometry.topHeight / 2)).fill(.black))
        .clipShape(IslandShape(bottomRadius: mode.showsCard ? 22 : (geometry.hasNotch ? 10 : geometry.topHeight / 2)))
        .opacity(mode == .hidden ? 0 : 1)
        .contentShape(Rectangle())
        .onHover { hud.isHovering = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.8), value: mode)
        .environment(\.colorScheme, .dark)
    }

    /// The row level with the notch: a red dot left of it and the timer right of it.
    @ViewBuilder
    private func topRow(geometry: NotchGeometry) -> some View {
        if let since = hud.recordingSince, hud.showsRecording {
            HStack(spacing: 0) {
                RecordingDot()
                    .frame(width: NotchGeometry.wing)
                if geometry.hasNotch {
                    Spacer(minLength: geometry.notchWidth)
                }
                ElapsedTime(since: since)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: NotchGeometry.wing)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { hud.isExpanded.toggle() }
            .help("Recording · click for details")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recording")
            .accessibilityAddTraits(.isButton)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func card(_ mode: NotchHUD.Mode) -> some View {
        switch mode {
        case .announcement(.started(let title)):
            CardRow(icon: { RecordingBadge() }, title: "Recording", subtitle: title)
        case .announcement(.stopped(let title, let duration)):
            CardRow(icon: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
            }, title: "Recording saved", subtitle: [title, Self.durationText(duration)].filter { !$0.isEmpty }.joined(separator: " · "))
        case .reminder(let reminder):
            ReminderCard(reminder: reminder, reminders: hud.reminders)
        case .recordingDetails:
            CardRow(icon: { RecordingBadge() }, title: "Recording", subtitle: hud.liveTitle) {
                HStack(spacing: 8) {
                    IslandButton(title: "Open", tint: .white.opacity(0.16), action: hud.openRecording)
                    Button(action: hud.stopRecording) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Theme.record, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Stop recording")
                }
            }
        case .hidden, .pill:
            EmptyView()
        }
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "\(Int(seconds)) s" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

private struct ReminderCard: View {
    let reminder: MeetingReminder
    let reminders: MeetingReminders

    var body: some View {
        let meeting = reminder.meeting
        CardRow(icon: {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }, title: meeting.title, subtitle: nil, countdownTo: meeting.start) {
            HStack(spacing: 6) {
                if meeting.link != nil {
                    IslandButton(title: "Join", tint: .green, action: reminders.join)
                        .help(reminders.recordsWhenJoining ? "Join the call and record it" : "Join the call")
                } else {
                    IslandButton(title: "Record", tint: Theme.record, action: reminders.recordNow)
                }
                Button(action: reminders.dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
    }
}

/// Icon, two lines of text, and optional buttons on the right.
private struct CardRow<Icon: View, Accessory: View>: View {
    @ViewBuilder let icon: Icon
    let title: String
    let subtitle: String?
    var countdownTo: Date? = nil
    @ViewBuilder var accessory: Accessory

    init(@ViewBuilder icon: () -> Icon, title: String, subtitle: String?, countdownTo: Date? = nil,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.icon = icon()
        self.title = title
        self.subtitle = subtitle
        self.countdownTo = countdownTo
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let countdownTo {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let soon = countdownTo.timeIntervalSince(context.date) < 60
                        Text(MeetingCountdown.text(until: countdownTo, now: context.date))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(soon ? Color.orange : Color.white.opacity(0.6))
                    }
                } else if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            accessory
        }
    }
}

private struct IslandButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(tint, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct RecordingDot: View {
    var body: some View {
        Circle()
            .fill(Theme.record)
            .frame(width: 8, height: 8)
            .shadow(color: Theme.record.opacity(0.8), radius: 4)
            .phaseAnimator([1.0, 0.4]) { view, opacity in view.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.9) }
    }
}

private struct RecordingBadge: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.record.opacity(0.22)).frame(width: 34, height: 34)
            Circle().fill(Theme.record).frame(width: 14, height: 14)
        }
    }
}

/// Square on top, flush with the screen edge, rounded below, like the notch it grows from.
struct IslandShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
            .path(in: rect)
    }
}
