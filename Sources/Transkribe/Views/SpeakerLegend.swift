import SwiftUI
import TranskribeCore

/// Lets the user correct speaker detection: "there were really 2 people".
struct SpeakerCountMenu: View {
    let transcript: Transcript
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Section("How many people are talking?") {
                Button("Detect Automatically") { model.setSpeakerCount(nil, for: transcript.id) }
                ForEach(1...6, id: \.self) { count in
                    Button(count == 1 ? "1 person" : "\(count) people") { model.setSpeakerCount(count, for: transcript.id) }
                }
            }
        } label: {
            Label(transcript.hasSpeakers ? "Adjust" : "Identify Speakers", systemImage: "person.2.badge.gearshape")
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(transcript.status != .done || model.activity[transcript.id] != nil)
        .help("Wrong number of speakers? Tell Transkribe how many people are talking.")
    }
}

/// Who took part and how much each person talked. Click a name to rename it.
struct SpeakerLegend: View {
    let transcript: Transcript

    var body: some View {
        let shares = SpeakerStats.shares(of: transcript.segments)
        VStack(alignment: .leading, spacing: 12) {
            // Proportional talk-time bar.
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(shares) { share in
                        Theme.color(for: share.speaker)
                            .frame(width: max(4, geometry.size.width * share.fraction - 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)

            FlowLayout(spacing: 8) {
                ForEach(shares) { share in
                    SpeakerChip(transcript: transcript, share: share)
                }
                SpeakerCountMenu(transcript: transcript)
            }
        }
    }
}

private struct SpeakerChip: View {
    let transcript: Transcript
    let share: SpeakerShare
    @Environment(AppModel.self) private var model
    @State private var isEditing = false
    @State private var name = ""

    var body: some View {
        let displayName = transcript.name(of: share.speaker)
        Button {
            name = transcript.speakerNames[share.speaker] ?? ""
            isEditing = true
        } label: {
            HStack(spacing: 7) {
                SpeakerAvatar(name: displayName, speaker: share.speaker, size: 20)
                Text(displayName).fontWeight(.medium)
                Text(share.fraction.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
            .padding(.leading, 4)
            .padding(.trailing, 11)
            .padding(.vertical, 4)
            .background(Theme.color(for: share.speaker).opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(displayName) · \(formattedTime) · \(share.turns) turns. Click to rename, right-click to merge.")
        .contextMenu {
            Button("Rename…") {
                name = transcript.speakerNames[share.speaker] ?? ""
                isEditing = true
            }
            Menu("Merge Into") {
                ForEach(transcript.speakers.filter { $0 != share.speaker }, id: \.self) { other in
                    Button(transcript.name(of: other)) {
                        model.mergeSpeaker(share.speaker, into: other, in: transcript.id)
                    }
                }
            }
        }
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename speaker").font(.headline)
                TextField(displayName, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(save)
                HStack {
                    Spacer()
                    Button("Cancel") { isEditing = false }
                    Button("Save", action: save).keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }

    private var formattedTime: String {
        Duration.seconds(share.seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    private func save() {
        model.renameSpeaker(share.speaker, in: transcript.id, to: name)
        isEditing = false
    }
}

/// Wraps children onto new lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let previous = rows[rows.count - 1]
                rows.append(Row(y: previous.y + previous.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
