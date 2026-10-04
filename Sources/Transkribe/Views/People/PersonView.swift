import SwiftUI
import TranskribeCore

/// Everything with one person: their details, every conversation, and a quick way to talk again.
struct PersonView: View {
    let person: Person
    @Environment(AppModel.self) private var model
    @State private var isEditing = false
    @State private var name = ""
    @State private var emails = ""

    var body: some View {
        let conversations = model.conversations(with: person.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .center, spacing: 22) {
                    PersonAvatar(initials: person.initials, seed: person.name, size: 92)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(person.name).font(.system(size: 34, weight: .bold, design: .rounded))
                        if !person.emails.isEmpty {
                            HStack(spacing: 10) {
                                ForEach(person.emails, id: \.self) { email in
                                    Link(destination: URL(string: "mailto:\(email)")!) {
                                        Label(email, systemImage: "envelope")
                                    }
                                    .font(.callout)
                                }
                            }
                        }
                        Text(summaryLine(conversations))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Button {
                            model.recordFollowUp(of: conversations.first, with: person.id)
                        } label: {
                            Label("Talk to \(person.name.split(separator: " ").first.map(String.init) ?? person.name)", systemImage: "record.circle")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Theme.record.gradient, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Record a conversation with \(person.name); it joins your ongoing conversation")
                        Button("Edit") {
                            name = person.name
                            emails = person.emails.joined(separator: ", ")
                            isEditing = true
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if conversations.isEmpty {
                    Text("No conversations yet. Link a voice to \(person.name) from any conversation, or record one now.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CONVERSATIONS").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 18)], spacing: 18) {
                            ForEach(conversations) { transcript in
                                ConversationCard(transcript: transcript, activity: model.activity[transcript.id])
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(AmbientBackground())
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
            Text("PEOPLE").font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(people) { person in
                        Button {
                            withAnimation(Theme.spring) { model.selectedPerson = person.id }
                        } label: {
                            VStack(spacing: 8) {
                                PersonAvatar(initials: person.initials, seed: person.name, size: 58)
                                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                                Text(person.name.split(separator: " ").first.map(String.init) ?? person.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text("\(model.conversations(with: person.id).count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(width: 76)
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
