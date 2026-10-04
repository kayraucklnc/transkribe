import SwiftUI
import TranskribeCore

/// Title, when and how long, and the people in the conversation.
struct ConversationHeader: View {
    let transcript: Transcript
    let isLive: Bool
    @Environment(AppModel.self) private var model
    @State private var title = ""

    var body: some View {
        VStack(spacing: 14) {
            TextField("Untitled", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .onSubmit { model.rename(transcript.id, to: title) }
            Text(meta)
                .font(.callout)
                .foregroundStyle(.secondary)
            if transcript.hasSpeakers {
                HStack(spacing: 10) {
                    ForEach(transcript.speakers, id: \.self) { speaker in
                        ParticipantChip(transcript: transcript, speaker: speaker)
                    }
                    if !isLive {
                        SpeakerCountMenu(transcript: transcript)
                    }
                }
            } else if transcript.status == .done, !transcript.segments.isEmpty, !isLive {
                SpeakerCountMenu(transcript: transcript)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { title = transcript.title }
        .onChange(of: transcript.title) { _, newValue in title = newValue }
    }

    private var meta: String {
        var parts = [transcript.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if !isLive { parts.append(TranscriptFormatter.timestamp(transcript.duration)) }
        if let code = transcript.language, let name = Locale.current.localizedString(forLanguageCode: code) {
            parts.append(name.capitalized(with: Locale.current))
        }
        return parts.joined(separator: " · ")
    }
}

/// A person in the conversation: avatar, name, share of talk time. Click for actions.
private struct ParticipantChip: View {
    let transcript: Transcript
    let speaker: Int
    @Environment(AppModel.self) private var model
    @State private var isRenaming = false
    @State private var name = ""

    var body: some View {
        let displayName = transcript.name(of: speaker)
        let share = SpeakerStats.shares(of: transcript.segments).first { $0.speaker == speaker }?.fraction ?? 0
        let isMe = transcript.resolvedMeSpeaker == speaker
        Menu {
            Button(isMe ? "This Isn't Me" : "This Is Me") { model.setMe(isMe ? nil : speaker, in: transcript.id) }
            Button("Rename…") {
                name = transcript.speakerNames[speaker] ?? ""
                isRenaming = true
            }
            Menu("Merge Into") {
                ForEach(transcript.speakers.filter { $0 != speaker }, id: \.self) { other in
                    Button(transcript.name(of: other)) { model.mergeSpeaker(speaker, into: other, in: transcript.id) }
                }
            }
        } label: {
            HStack(spacing: 7) {
                SpeakerAvatar(name: displayName, speaker: speaker, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayName).font(.callout.weight(.semibold))
                    Text(isMe ? "You · \(percent(share))" : percent(share))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(isMe ? Color.accentColor.opacity(0.14) : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.06)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename speaker").font(.headline)
                TextField(displayName, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit(save)
                HStack {
                    Spacer()
                    Button("Cancel") { isRenaming = false }
                    Button("Save", action: save).keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func save() {
        model.renameSpeaker(speaker, in: transcript.id, to: name)
        isRenaming = false
    }
}

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
            Image(systemName: transcript.hasSpeakers ? "person.2.badge.gearshape" : "person.2.wave.2")
                .font(.callout)
                .frame(width: 32, height: 32)
                .background(Theme.card, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.06)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(transcript.status != .done || model.activity[transcript.id] != nil)
        .help(transcript.hasSpeakers ? "Wrong number of people? Tell Transkribe how many were talking." : "Identify speakers")
    }
}

/// Shown once per conversation so the thread can be laid out like the user's own messages.
struct WhoIsMePrompt: View {
    let transcript: Transcript
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Text("Which one is you?")
                .font(.headline)
            Text("Your words will appear on the right, like messages you sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(transcript.speakers, id: \.self) { speaker in
                    Button {
                        withAnimation(Theme.spring) { model.setMe(speaker, in: transcript.id) }
                    } label: {
                        HStack(spacing: 6) {
                            SpeakerAvatar(name: transcript.name(of: speaker), speaker: speaker, size: 22)
                            Text(transcript.name(of: speaker))
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 12)
                        .padding(.vertical, 4)
                        .background(Theme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button("Not Me") { model.setMe(-1, in: transcript.id) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
