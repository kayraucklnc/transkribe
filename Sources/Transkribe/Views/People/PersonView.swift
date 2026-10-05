import SwiftUI
import TranskribeCore

/// Everything with one person: their details, every conversation, and a quick way to talk again.
struct PersonView: View {
    let person: Person
    @Environment(AppModel.self) private var model
    @State private var isEditing = false
    @State private var name = ""
    @State private var emails = ""
    @State private var isAsking = false
    @State private var askQuestion = ""
    @Environment(AIService.self) private var ai

    var body: some View {
        let conversations = model.conversations(with: person.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .center, spacing: 18) {
                    PersonAvatar(initials: person.initials, seed: person.name, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name).font(.system(size: 26, weight: .bold))
                        Text(summaryLine(conversations))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        if person.voiceprint != nil {
                            Label("Recognizes \(firstName)'s voice in new recordings", systemImage: "waveform.badge.checkmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.green)
                        }
                        if !person.emails.isEmpty {
                            HStack(spacing: 12) {
                                ForEach(person.emails, id: \.self) { email in
                                    Link(email, destination: URL(string: "mailto:\(email)")!)
                                        .font(.system(size: 13))
                                }
                            }
                        }
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button {
                        model.recordFollowUp(of: conversations.first, with: person.id)
                    } label: {
                        Label("Record with \(firstName)", systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.record)
                    .help("Record a conversation with \(person.name); it joins your ongoing conversation")
                    if !conversations.isEmpty {
                        Button {
                            ai.clearLibraryChat()
                            isAsking = true
                        } label: {
                            Label("Ask about \(firstName)", systemImage: "sparkle.magnifyingglass")
                        }
                        .help("Ask questions about everything you've talked about with \(person.name)")
                    }
                    Button("Edit") {
                        name = person.name
                        emails = person.emails.joined(separator: ", ")
                        isEditing = true
                    }
                }
                .controlSize(.large)
                if conversations.isEmpty {
                    Text("No conversations yet. Link a voice to \(person.name) from any conversation, or record one now.")
                        .foregroundStyle(.secondary)
                } else {
                    ConversationGroup(title: "Conversations", transcripts: conversations)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Stage.canvas)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(Theme.spring) { model.selectedPerson = nil }
                } label: {
                    Label("Library", systemImage: "chevron.left")
                }
            }
        }
        .onExitCommand { withAnimation(Theme.spring) { model.selectedPerson = nil } }
        .sheet(isPresented: $isAsking) {
            LibraryChatView(focus: person, question: $askQuestion)
        }
        .sheet(isPresented: $isEditing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit person").font(.headline)
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                TextField("Emails, separated by commas", text: $emails).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Delete Person", role: .destructive) {
                        isEditing = false
                        model.deletePerson(person.id)
                    }
                    Spacer()
                    Button("Cancel") { isEditing = false }
                    Button("Save") {
                        var updated = person
                        updated.name = name.trimmingCharacters(in: .whitespaces)
                        updated.emails = emails.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        model.updatePerson(updated)
                        isEditing = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
    }

    private var firstName: String { person.name.split(separator: " ").first.map(String.init) ?? person.name }

    private func summaryLine(_ conversations: [Transcript]) -> String {
        guard let latest = conversations.first else { return "No conversations yet" }
        let total = conversations.reduce(0) { $0 + $1.duration }
        let length = Duration.seconds(total).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        return "\(conversations.count) conversation\(conversations.count == 1 ? "" : "s") · \(length) together · last \(latest.createdAt.formatted(.relative(presentation: .named)))"
    }
}

/// The people you talk with, as a row of avatars on the home screen.
struct PeopleStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let people = model.people.sorted { model.conversations(with: $0.id).first?.createdAt ?? .distantPast > model.conversations(with: $1.id).first?.createdAt ?? .distantPast }
        VStack(alignment: .leading, spacing: 14) {
            Text("People")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(people) { person in
                        Button {
                            withAnimation(Theme.spring) { model.selectedPerson = person.id }
                        } label: {
                            VStack(spacing: 8) {
                                PersonAvatar(initials: person.initials, seed: person.name, size: 46)
                                Text(person.name.split(separator: " ").first.map(String.init) ?? person.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                            }
                            .frame(width: 64)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Record a Conversation") { model.recordFollowUp(of: model.conversations(with: person.id).first, with: person.id) }
                            Divider()
                            Button("Delete Person", role: .destructive) { model.deletePerson(person.id) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
