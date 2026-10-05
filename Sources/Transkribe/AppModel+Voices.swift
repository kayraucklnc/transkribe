import Foundation
import TranskribeCore

/// Recognizing people by voice: every finished conversation teaches the app what its speakers
/// sound like, and known voices are linked to their person automatically next time.
extension AppModel {
    private static let myVoiceKey = "myVoiceprint"
    private static let myVoiceSamplesKey = "myVoiceSamples"

    /// Learns each speaker's voice in `id` and, for a new conversation, recognizes known people.
    func learnVoices(of id: Transcript.ID, recognize: Bool) async {
        guard let transcript = transcript(id), transcript.status == .done, !transcript.segments.isEmpty else { return }
        var prints: [Int: [Float]] = [:]
        for speaker in transcript.speakers {
            guard let clips = try? await clips(of: speaker, in: transcript), !clips.isEmpty,
                  let print = try? await voiceprints.voiceprint(clips: clips) else { continue }
            prints[speaker] = print
        }
        guard !prints.isEmpty, self.transcript(id) != nil else { return }
        update(id, persist: true) { $0.speakerVoiceprints = prints }
        guard let current = self.transcript(id) else { return }

        // The main voice on the mic of a call is certainly the user.
        if current.tracks.contains(where: { $0.source == .system }), let mine = prints[SpeakerID.me] {
            learnMyVoice(mine)
        }
        // People already linked here (e.g. carried over from an ongoing conversation) teach their voice too.
        for (speaker, person) in current.speakerPeople {
            if let print = prints[speaker] { learnVoice(print, of: person) }
        }
        if recognize { recognizeVoices(in: id) }
    }

    /// Links unknown voices to known people, and finds "Me" in recordings without a call.
    private func recognizeVoices(in id: Transcript.ID) {
        guard let transcript = transcript(id) else { return }
        var me = transcript.resolvedMeSpeaker
        if me == nil, transcript.hasSpeakers, let mine = myVoiceprint {
            let match = VoiceMatcher.match(voices: transcript.speakerVoiceprints, people: [(id: Self.meMarker, voiceprint: mine)])
            if let speaker = match.first(where: { $0.value == Self.meMarker })?.key {
                setMe(speaker, in: id)
                me = speaker
            }
        }
        let unknown = transcript.speakerVoiceprints.filter { speaker, _ in
            speaker != me && transcript.speakerPeople[speaker] == nil && transcript.speakerNames[speaker] == nil
        }
        let known = people.compactMap { person in person.voiceprint.map { (id: person.id, voiceprint: $0) } }
            .filter { candidate in !transcript.speakerPeople.values.contains(candidate.id) }
        let matches = VoiceMatcher.match(voices: unknown, people: known)
        guard !matches.isEmpty else { return }
        update(id, persist: true) { transcript in
            for (speaker, personID) in matches {
                transcript.speakerPeople[speaker] = personID
                transcript.speakerNames[speaker] = people.first { $0.id == personID }?.name
            }
        }
        let names = matches.values.compactMap { personID in people.first { $0.id == personID }?.name }
        showToast("Recognized \(ListFormatter.localizedString(byJoining: names)) by voice")
    }

    func learnVoice(_ print: [Float], of personID: Person.ID) {
        guard let index = people.firstIndex(where: { $0.id == personID }) else { return }
        var person = people[index]
        let samples = person.voiceSamples ?? 0
        person.voiceprint = Voiceprint.merge(person.voiceprint, weight: min(samples, 20), with: print)
        person.voiceSamples = samples + 1
        people[index] = person
        savePeople()
    }

    func learnMyVoice(_ print: [Float]) {
        let defaults = UserDefaults.standard
        let samples = defaults.integer(forKey: Self.myVoiceSamplesKey)
        let merged = Voiceprint.merge(myVoiceprint, weight: min(samples, 20), with: print)
        defaults.set(try? JSONEncoder().encode(merged), forKey: Self.myVoiceKey)
        defaults.set(samples + 1, forKey: Self.myVoiceSamplesKey)
    }

    var myVoiceprint: [Float]? {
        UserDefaults.standard.data(forKey: Self.myVoiceKey).flatMap { try? JSONDecoder().decode([Float].self, from: $0) }
    }

    /// Learns voices for conversations recorded before voice recognition existed, one at a time,
    /// only while the Mac has room for it.
    func backfillVoices() {
        Task(priority: .background) { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            while let self, !Task.isCancelled {
                guard let next = self.transcripts.first(where: {
                    $0.status == .done && $0.speakerVoiceprints.isEmpty && !$0.segments.isEmpty && $0.speakers.count > 0
                }) else { return }
                if ResourceGovernor.currentPauseReason() != nil || self.isTranscribingSomething || self.isRecording {
                    try? await Task.sleep(for: .seconds(60))
                    continue
                }
                await self.learnVoices(of: next.id, recognize: false)
                if self.transcript(next.id)?.speakerVoiceprints.isEmpty ?? false {
                    // Nothing usable (e.g. very short): mark it so it isn't retried forever.
                    self.update(next.id, persist: true) { $0.speakerVoiceprints = [-1: []] }
                }
            }
        }
    }

    private static let meMarker = UUID(uuidString: "00000000-0000-0000-0000-00000000000E")!

    /// Audio of `speaker` talking alone, read from the track their voice is on.
    private func clips(of speaker: Int, in transcript: Transcript) async throws -> [[Float]] {
        let withCall = transcript.tracks.contains { $0.source == .system } && transcript.tracks.contains { $0.source == .microphone }
        let track = transcript.tracks.first { track in
            guard withCall else { return true }
            return SpeakerID.isOnMicrophone(speaker) ? track.source == .microphone : track.source == .system
        }
        guard let track else { return [] }
        let source = FileAudioSource(url: store.audioURL(for: transcript, track: track))
        var clips: [[Float]] = []
        for range in VoiceClips.ranges(for: speaker, in: transcript.segments) {
            let start = range.start - track.offset, end = range.end - track.offset
            guard start >= 0 else { continue }
            clips.append(try await source.read(from: start, to: end))
        }
        return clips
    }
}
