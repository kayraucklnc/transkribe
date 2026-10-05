import SwiftUI
import TranskribeCore

/// "Who is this?" — pick someone you know, someone from Contacts, or add a new person.
struct LinkPersonPopover: View {
    let transcript: Transcript
    let speaker: Int
    let onDone: () -> Void
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var email = ""
    @State private var contacts: [ContactsSearch.Match] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Who is \(transcript.name(of: speaker))?").font(.headline)
            TextField("Name", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(createIfNeeded)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matchingPeople) { person in
                        row(title: person.name, subtitle: person.emails.first ?? "\(model.conversations(with: person.id).count) conversations",
                            badge: person.initials, speaker: speaker) {
                            model.link(speaker: speaker, in: transcript.id, to: person)
                            onDone()
                        }
                    }
                    ForEach(contacts.filter { match in !model.people.contains { $0.contactIdentifier == match.id } }) { match in
                        row(title: match.name, subtitle: match.emails.first ?? "From Contacts", badge: nil, speaker: speaker) {
                            let person = model.addPerson(name: match.name, emails: match.emails, contactIdentifier: match.id)
                            model.link(speaker: speaker, in: transcript.id, to: person)
                            onDone()
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            if !query.trimmingCharacters(in: .whitespaces).isEmpty, !exactMatch {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Email (optional)", text: $email).textFieldStyle(.roundedBorder)
                    Button {
                        createIfNeeded()
                    } label: {
                        Label("Add “\(query.trimmingCharacters(in: .whitespaces))”", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            focused = true
            query = transcript.speakerNames[speaker] ?? ""
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else { contacts = []; return }
            try? await Task.sleep(for: .milliseconds(200))
            contacts = await ContactsSearch.search(trimmed)
        }
    }

    private var matchingPeople: [Person] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return model.people }
        return model.people.filter { person in
            TranscriptSearch.normalize(person.name).contains(TranscriptSearch.normalize(trimmed))
                || person.emails.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    private var exactMatch: Bool {
        model.people.contains { TranscriptSearch.normalize($0.name) == TranscriptSearch.normalize(query.trimmingCharacters(in: .whitespaces)) }
    }

    private func createIfNeeded() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let person = model.people.first { TranscriptSearch.normalize($0.name) == TranscriptSearch.normalize(name) }
            ?? model.addPerson(name: name, emails: email.isEmpty ? [] : [email.trimmingCharacters(in: .whitespaces)])
        model.link(speaker: speaker, in: transcript.id, to: person)
        onDone()
    }

    private func row(title: String, subtitle: String, badge: String?, speaker: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PersonAvatar(initials: badge ?? String(title.prefix(1)), seed: title, size: 28, fromContacts: badge == nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A person's avatar: initials on a color derived from their name.
struct PersonAvatar: View {
    /// `hashValue` changes every launch; this keeps a person's color the same forever.
    private var stableIndex: Int {
        seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % Theme.speakerColors.count
    }

    let initials: String
    let seed: String
    var size: CGFloat = 32
    var fromContacts = false

    var body: some View {
        Text(initials.prefix(2).uppercased())
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.speakerColors[stableIndex], in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if fromContacts {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(.white, .gray)
                        .offset(x: 2, y: 2)
                }
            }
    }
}
