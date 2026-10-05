import Contacts
import Foundation
import TranskribeCore

extension AppModel {
    // MARK: - People

    func loadPeople() {
        people = (try? peopleStore.load()) ?? []
    }

    func savePeople() {
        do { try peopleStore.save(people) } catch { show(error) }
    }

    @discardableResult
    func addPerson(name: String, emails: [String] = [], contactIdentifier: String? = nil) -> Person {
        if let contactIdentifier, let existing = people.first(where: { $0.contactIdentifier == contactIdentifier }) {
            return existing
        }
        let person = Person(name: name.trimmingCharacters(in: .whitespacesAndNewlines), emails: emails, contactIdentifier: contactIdentifier)
        people.append(person)
        savePeople()
        return person
    }

    func updatePerson(_ person: Person) {
        guard let index = people.firstIndex(where: { $0.id == person.id }) else { return }
        people[index] = person
        savePeople()
        // Keep names in conversations in step with the person.
        for transcript in transcripts where transcript.speakerPeople.values.contains(person.id) {
            update(transcript.id, persist: true) { item in
                for (speaker, id) in item.speakerPeople where id == person.id { item.speakerNames[speaker] = person.name }
            }
        }
    }

    func deletePerson(_ id: Person.ID) {
        people.removeAll { $0.id == id }
        savePeople()
        for transcript in transcripts where transcript.speakerPeople.values.contains(id) {
            update(transcript.id, persist: true) { item in item.speakerPeople = item.speakerPeople.filter { $0.value != id } }
        }
        if selectedPerson == id { selectedPerson = nil }
    }

    /// Ties a voice in a conversation to a person; the person's name replaces the label.
    func link(speaker: Int, in id: Transcript.ID, to person: Person) {
        update(id, persist: true) {
            $0.speakerPeople[speaker] = person.id
            $0.speakerNames[speaker] = person.name
        }
        if let print = transcript(id)?.speakerVoiceprints[speaker] { learnVoice(print, of: person.id) }
        showToast("Linked to \(person.name) · Transkribe will recognize their voice")
    }

    func unlink(speaker: Int, in id: Transcript.ID) {
        update(id, persist: true) { $0.speakerPeople[speaker] = nil }
    }

    func conversations(with person: Person.ID) -> [Transcript] {
        Conversations.with(person, in: transcripts)
    }

    // MARK: - Ongoing conversations

    /// Makes `source` part of the same ongoing conversation as `target`.
    func addToConversation(_ source: Transcript.ID, joining target: Transcript.ID) {
        guard source != target, let targetTranscript = transcript(target) else { return }
        let thread = targetTranscript.threadID ?? transcript(source)?.threadID ?? UUID()
        update(target, persist: true) { $0.threadID = thread }
        update(source, persist: true) { $0.threadID = thread }
        // Bring over who's who when it's obvious (one other person in both).
        if let person = singleOtherPerson(in: targetTranscript), let source = transcript(source) {
            let others = source.speakers.filter { $0 != source.resolvedMeSpeaker }
            if others.count == 1, source.speakerPeople[others[0]] == nil,
               let match = people.first(where: { $0.id == person }) {
                link(speaker: others[0], in: source.id, to: match)
            }
        }
        showToast("Added to the conversation")
    }

    func removeFromConversation(_ id: Transcript.ID) {
        update(id, persist: true) { $0.threadID = nil }
    }

    func sessions(of transcript: Transcript) -> [Transcript] {
        guard let thread = transcript.threadID else { return [transcript] }
        return Conversations.sessions(in: thread, from: transcripts)
    }

    /// Records a new part of an existing conversation, or a new conversation with a person.
    func recordFollowUp(of transcript: Transcript? = nil, with person: Person.ID? = nil) {
        pendingFollowUp = (transcript?.id, person ?? transcript.flatMap(singleOtherPerson(in:)))
        startRecording()
    }

    /// Called when a recording's transcript is finished: joins the pending thread and links the person.
    func applyPendingFollowUp(to id: Transcript.ID) {
        guard let pending = pendingFollowUp else { return }
        pendingFollowUp = nil
        if let previous = pending.transcript { addToConversation(id, joining: previous) }
        if let personID = pending.person, let person = people.first(where: { $0.id == personID }),
           let transcript = transcript(id) {
            let others = transcript.speakers.filter { $0 != transcript.resolvedMeSpeaker }
            if others.count == 1 { link(speaker: others[0], in: id, to: person) }
        }
    }

    private func singleOtherPerson(in transcript: Transcript) -> Person.ID? {
        let linked = Set(transcript.speakerPeople.filter { $0.key != transcript.resolvedMeSpeaker }.values)
        return linked.count == 1 ? linked.first : nil
    }
}

/// Finds people in the user's Contacts.
enum ContactsSearch {
    struct Match: Identifiable {
        var id: String
        var name: String
        var emails: [String]
    }

    static func search(_ query: String) async -> [Match] {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            guard (try? await store.requestAccess(for: .contacts)) == true else { return [] }
        } else if status != .authorized {
            return []
        }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        return contacts.prefix(8).map { contact in
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            return Match(id: contact.identifier, name: name.isEmpty ? contact.organizationName : name,
                         emails: contact.emailAddresses.map { $0.value as String })
        }
    }
}
