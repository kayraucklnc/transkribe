import AppKit
import SwiftUI
import TranskribeCore

/// A borderless panel that floats above everything without taking focus away from the app
/// you're typing in.
@MainActor
final class DictationPanelHost {
    private var panel: NSPanel?

    func show(controller: DictationController) {
        let panel = panel ?? makePanel(controller: controller)
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 18))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        // Let the pill's exit animation play before the window goes.
        let panel = panel
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            panel?.orderOut(nil)
        }
    }

    private func makePanel(controller: DictationController) -> NSPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
                                  styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        let host = NSHostingView(rootView: DictationPill(controller: controller))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The pill: a dark capsule with a live waveform, which turns into a short confirmation.
struct DictationPill: View {
    let controller: DictationController

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if controller.phase != .hidden {
                if controller.showsHint, controller.phase == .listening {
                    Hint()
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
                capsule
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: controller.phase)
        .animation(.easeOut(duration: 0.3), value: controller.showsHint)
    }

    private var capsule: some View {
        ZStack {
            switch controller.phase {
            case .listening:
                Waveform(levels: controller.levels)
                    .transition(.opacity)
            case .transcribing:
                Thinking()
                    .transition(.opacity)
            case .finished(let outcome):
                Result(outcome: outcome)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            case .hidden:
                EmptyView()
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .frame(minWidth: 156)
        .background {
            Capsule()
                .fill(Color(white: 0.09).opacity(0.94))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.13), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
        .contentShape(Capsule())
        .onTapGesture {
            if controller.phase == .listening { controller.finish() }
        }
        .help("Return to insert · Esc to cancel")
        .environment(\.colorScheme, .dark)
    }
}

/// Thin white bars, tall in the middle and dotted at the edges, moving with your voice.
private struct Waveform: View {
    let levels: [Double]
    static let count = 23

    var body: some View {
        let heights = DictationLevel.bars(count: Self.count, history: levels)
        HStack(spacing: 2.5) {
            ForEach(0..<Self.count, id: \.self) { index in
                let edge = abs(Double(index) - Double(Self.count - 1) / 2) / (Double(Self.count) / 2)
                Capsule()
                    .fill(Color.white.opacity(1 - edge * 0.55))
                    .frame(width: 2.5, height: 2.5 + 19.5 * heights[index])
            }
        }
        .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.7), value: heights)
    }
}

/// While the words are worked out: a soft ripple across the dots.
private struct Thinking: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<Waveform.count, id: \.self) { index in
                    let wave = (sin(time * 6 - Double(index) * 0.45) + 1) / 2
                    Capsule()
                        .fill(Color.white.opacity(0.35 + 0.65 * wave))
                        .frame(width: 2.5, height: 2.5 + 5 * wave)
                }
            }
        }
    }
}

private struct Result: View {
    let outcome: DictationController.Outcome

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: outcome)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    private var symbol: String {
        switch outcome {
        case .pasted: "checkmark"
        case .copied: "doc.on.clipboard"
        case .nothingHeard: "waveform.slash"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch outcome {
        case .pasted: .green
        case .copied: .white
        case .nothingHeard: .white.opacity(0.6)
        case .failed: .orange
        }
    }

    private var title: String {
        switch outcome {
        case .pasted: "Inserted"
        case .copied: "Copied — press ⌘V"
        case .nothingHeard: "Didn't catch that"
        case .failed(let message): message
        }
    }
}

private struct Hint: View {
    var body: some View {
        HStack(spacing: 12) {
            key("return", "Insert")
            key("esc", "Cancel")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(white: 0.09).opacity(0.85)))
        .environment(\.colorScheme, .dark)
    }

    private func key(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.35)))
            Text(label)
        }
    }
}
