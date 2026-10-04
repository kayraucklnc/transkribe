import Foundation

/// Every prompt Transkribe sends to a model, in one place so they are easy to tune.
///
/// Two sizes exist: the full prompts for large-context models, and `compact` ones for small
/// on-device models where every token of instructions is taken from the transcript.
public enum Prompts {
    // MARK: - Shared pieces

    /// English name of a Whisper language code ("tr" → "Turkish"), or nil if unknown.
    static func languageName(for code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return Locale(identifier: "en").localizedString(forLanguageCode: base)
    }

    static func outputLanguageInstruction(for transcript: Transcript) -> String {
        guard let name = languageName(for: transcript.language) else {
            return "Write in the language the conversation is held in (if it mixes languages, use the main one), including the section headings."
        }
        var text = "The conversation is in \(name). Write in \(name), including the section headings"
        if let headings = localizedHeadings[transcript.language?.lowercased().prefix(2).description ?? ""] {
            text += " (use: \(headings))"
        } else if name != "English" {
            text += " (translate them)"
        }
        return text + ". Keep names, product names and technical terms as they appear in the transcript."
    }

    /// Summary section headings, written into the template itself: models follow a literal
    /// template over an instruction to translate it.
    struct SectionHeadings {
        var tldr = "TL;DR", keyPoints = "Key points", decisions = "Decisions", actions = "Action items"
        var openQuestions = "Open questions", whoSaidWhat = "Who said what", unassigned = "Unassigned"
    }

    static func headings(for transcript: Transcript) -> SectionHeadings {
        switch transcript.language?.lowercased().prefix(2) {
        case "tr": SectionHeadings(tldr: "Özet", keyPoints: "Önemli noktalar", decisions: "Kararlar", actions: "Yapılacaklar",
                                   openQuestions: "Açık sorular", whoSaidWhat: "Kim ne dedi", unassigned: "Atanmadı")
        case "de": SectionHeadings(tldr: "Kurzfassung", keyPoints: "Wichtige Punkte", decisions: "Entscheidungen", actions: "Aufgaben",
                                   openQuestions: "Offene Fragen", whoSaidWhat: "Wer hat was gesagt", unassigned: "Nicht zugewiesen")
        case "fr": SectionHeadings(tldr: "En bref", keyPoints: "Points clés", decisions: "Décisions", actions: "Actions",
                                   openQuestions: "Questions ouvertes", whoSaidWhat: "Qui a dit quoi", unassigned: "Non attribué")
        case "es": SectionHeadings(tldr: "Resumen", keyPoints: "Puntos clave", decisions: "Decisiones", actions: "Tareas",
                                   openQuestions: "Preguntas abiertas", whoSaidWhat: "Quién dijo qué", unassigned: "Sin asignar")
        default: SectionHeadings()
        }
    }

    /// Section headings for languages users are likely to use, so the model doesn't improvise.
    static let localizedHeadings: [String: String] = [
        "tr": "Özet, Önemli noktalar, Kararlar, Yapılacaklar, Açık sorular, Kim ne dedi; unassigned owner: Atanmadı",
        "de": "Kurzfassung, Wichtige Punkte, Entscheidungen, Aufgaben, Offene Fragen, Wer hat was gesagt; unassigned owner: Nicht zugewiesen",
        "fr": "En bref, Points clés, Décisions, Actions, Questions ouvertes, Qui a dit quoi; unassigned owner: Non attribué",
        "es": "Resumen, Puntos clave, Decisiones, Tareas, Preguntas abiertas, Quién dijo qué; unassigned owner: Sin asignar",
    ]

    /// What the model should know about the recording before reading it.
    static func conversationInfo(for transcript: Transcript) -> String {
        var lines = [
            "Title: \(transcript.title)",
            "Recorded: \(dateFormatter.string(from: transcript.createdAt))",
        ]
        if transcript.duration > 0 {
            lines.append("Length: \(TranscriptFormatter.timestamp(transcript.duration))")
        }
        if let name = languageName(for: transcript.language) {
            lines.append("Detected language: \(name)")
        }
        if transcript.hasSpeakers {
            let names = transcript.speakers.map(transcript.name(of:)).joined(separator: ", ")
            lines.append("Speakers (in order of first appearance): \(names)")
            lines.append("Speaker labels come from automatic speaker detection and can be wrong. Generic labels like \"Speaker 2\" are placeholders, not names.")
            if transcript.speakers.contains(SpeakerID.me) {
                lines.append("\"\(transcript.name(of: SpeakerID.me))\" is the person who recorded this, captured by their own microphone; that label is reliable.")
            }
        } else {
            lines.append("Speakers were not separated: lines have no speaker labels.")
        }
        return lines.joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        return formatter
    }()

    private static let sourceNote = """
    The transcript was made automatically: speech recognition (Whisper) produced the text and \
    automatic speaker detection produced the speaker labels. Each line starts with the time it was \
    said, like [12:34] or [1:02:03].
    """

    // MARK: - Summary

    /// System prompt for a summary. `fromNotes` is used for the final step of map-reduce,
    /// where the model sees notes on each part instead of the transcript itself.
    public static func summarySystem(for transcript: Transcript, compact: Bool, fromNotes: Bool = false) -> String {
        let input = fromNotes
            ? "You get notes taken on consecutive parts of a long conversation, instead of the full transcript. The timestamps in the notes come from the transcript and can be cited. Parts can overlap in topic: merge repeated points instead of listing them twice."
            : "You get the transcript of a conversation."
        let language = outputLanguageInstruction(for: transcript)
        return compact
            ? compactSummarySystem(input: input, language: language, hasSpeakers: transcript.hasSpeakers)
            : fullSummarySystem(input: input, language: language, hasSpeakers: transcript.hasSpeakers, headings: headings(for: transcript))
    }

    private static func fullSummarySystem(input: String, language: String, hasSpeakers: Bool, headings h: SectionHeadings) -> String {
        let speakerAccuracy = hasSpeakers
            ? """
            - Speaker labels may be wrong: one person can be split across two labels, or two people merged \
            into one. If attributions look inconsistent (someone answering their own question, a sudden change \
            of opinion), say briefly that the attribution is uncertain instead of building conclusions on it.
            - Use a real name for a generic label like "Speaker 2" only if people in the transcript clearly \
            address that person by name, and mark it: "Speaker 2 (probably Ayşe)".
            """
            : "- There are no speaker labels, so don't guess who said what; attribute points to people only when the transcript names them (\"Ali said he'd send it\")."
        let whoSaidWhat = hasSpeakers
            ? """

            ## \(h.whoSaidWhat)
            One line per participant: `- **Name** — their role or position and main contributions, in one sentence`. \
            Use the speaker names exactly as they appear in the transcript.
            """
            : ""
        return """
        You write summaries of recorded conversations for the user of Transkribe, a private transcription app. \
        Conversations range from work meetings and interviews to lectures and casual phone calls; adapt to what this one is. \
        \(input) \(sourceNote)

        <language>
        \(language)
        </language>

        <accuracy>
        - Use only what the transcript says. Never invent names, numbers, dates, owners, deadlines or decisions. \
        If something is implied but not said outright, say so ("seems to", "probably") or leave it out.
        - Speech recognition makes mistakes: misheard words, garbled names, wrong numbers. When an unclear passage \
        matters, say it's unclear rather than guessing, and don't silently "correct" names or figures.
        \(speakerAccuracy)
        - A proposal is not a decision, and "we should look into it" is not an action item with an owner. Don't upgrade them.
        </accuracy>

        <citations>
        Back up key points, decisions and action items with the timestamp of the line where they are said, \
        copied exactly, e.g. "Launch moves to March [12:34]". One or two timestamps per bullet at most. \
        Only cite timestamps that appear in the input.
        </citations>

        <format>
        Markdown with these sections, in this order, as level-2 headings written exactly as shown. Leave out any section that would \
        be empty; never write "None" or "N/A".

        ## \(h.tldr)
        One short paragraph (2–4 sentences): what the conversation was about and what came out of it.

        ## \(h.keyPoints)
        Bullets with the substance: facts, arguments, numbers, problems raised. Most important first; merge repetition.

        ## \(h.decisions)
        Bullets with what was actually agreed or decided.

        ## \(h.actions)
        A checklist, one task per line: `- [ ] Owner — task (due: deadline)`. The owner is whoever committed \
        to the task or was asked to do it; write "\(h.unassigned)" if nobody was. Add the \
        due part only when a deadline was mentioned.

        ## \(h.openQuestions)
        Bullets with unanswered questions, unresolved disagreements and things left to follow up.
        \(whoSaidWhat)
        </format>

        <style>
        Concise and concrete: prefer specifics (numbers, names, dates, examples) over generalities. Let length \
        follow substance: a five-minute call needs a few bullets, a two-hour meeting may need many. No preamble \
        or closing remarks; start directly with the first heading.
        </style>
        """
    }

    private static func compactSummarySystem(input: String, language: String, hasSpeakers: Bool) -> String {
        """
        You summarize recorded conversations. \(input) \(sourceNote)
        \(language)
        Rules:
        - Use only what the transcript says. Never invent names, numbers, dates, owners or decisions. If a passage is unclear, say so.
        \(hasSpeakers ? "- Speaker labels come from automatic detection and may be wrong; say so if attributions look inconsistent.\n" : "")\
        - Cite the timestamp of the line you rely on, copied exactly, like [12:34].
        Write Markdown with these level-2 headings, in order, leaving out empty ones:
        ## TL;DR: one short paragraph.
        ## Key points: bullets, most important first.
        ## Decisions: what was agreed.
        ## Action items: checklist lines `- [ ] Owner — task (due: deadline)`; due only if mentioned.
        ## Open questions: bullets.
        \(hasSpeakers ? "## Who said what: one line per speaker, `- **Name** — role and main points`.\n" : "")\
        No preamble; start with the first heading.
        """
    }

    public static func summaryUser(transcript: Transcript, rendered: String) -> String {
        """
        <conversation_info>
        \(conversationInfo(for: transcript))
        </conversation_info>

        <transcript>
        \(rendered)
        </transcript>

        Summarize this conversation following the instructions.
        """
    }

    // MARK: - Map-reduce

    /// Map step: notes on one part of a transcript too long for a single request.
    public static func partialNotesSystem(for transcript: Transcript) -> String {
        let language = languageName(for: transcript.language).map { "Write the notes in \($0)." }
            ?? "Write the notes in the language of the conversation."
        return """
        You take notes on one part of a long recorded conversation. \(sourceNote) Your notes will be \
        combined with notes on the other parts to write one summary of the whole conversation, so capture \
        everything that could matter there:
        - topics discussed and the substance: facts, numbers, arguments, problems
        - decisions, and proposals that were not decided
        - commitments and tasks, with who owns them and any deadline
        - open questions and disagreements
        - each speaker's role and positions, by their label
        Rules: use only what this part says; never invent anything. End every note with the timestamp of \
        its line, copied exactly, like [12:34]. Mark unclear passages as unclear. Terse bullet notes, no \
        intro or conclusion. \(language)
        """
    }

    public static func partialNotesUser(transcript: Transcript, chunk: String, part: Int, of total: Int) -> String {
        """
        <conversation_info>
        \(conversationInfo(for: transcript))
        </conversation_info>

        <transcript_part number="\(part)" of="\(total)">
        \(chunk)
        </transcript_part>

        Write your notes on this part.
        """
    }

    /// Used when the notes on all parts are themselves too long for one request.
    public static func condenseNotesSystem(for transcript: Transcript) -> String {
        partialNotesSystem(for: transcript) + """

        You are given earlier notes on several consecutive parts instead of transcript lines. Merge them \
        into one shorter set of notes: drop repetition, keep every decision, task, owner, deadline, number \
        and open question, and keep the timestamps.
        """
    }

    public static func notesUser(transcript: Transcript, notes: [String], instruction: String) -> String {
        let parts = notes.enumerated().map { index, note in
            "<notes part=\"\(index + 1)\">\n\(note)\n</notes>"
        }
        return """
        <conversation_info>
        \(conversationInfo(for: transcript))
        </conversation_info>

        \(parts.joined(separator: "\n\n"))

        \(instruction)
        """
    }

    static let reduceInstruction = "Write the summary of the whole conversation from these notes, following the instructions."
    static let condenseInstruction = "Merge these notes into one shorter set of notes."

    // MARK: - Q&A

    /// System prompt for questions about a transcript. `context` is the rendered transcript,
    /// or retrieved excerpts when `isExcerpt` is true.
    public static func questionSystem(for transcript: Transcript, context: String, isExcerpt: Bool, compact: Bool) -> String {
        let scope = isExcerpt
            ? """
            The transcript is too long to show in full. Below are only the excerpts that look most relevant \
            to the latest question; "\(TranscriptRetriever.gapMarker)" marks skipped parts. If the excerpts \
            don't contain the answer, say you couldn't find it in the parts you can see (it may be elsewhere \
            in the recording) rather than saying the conversation never covers it.
            """
            : "Below is the full transcript."
        let rules = compact ? compactQuestionRules : fullQuestionRules
        return """
        You answer questions about a recorded conversation for the user of Transkribe, a private \
        transcription app. \(sourceNote)

        \(rules)

        \(scope)

        <conversation_info>
        \(conversationInfo(for: transcript))
        </conversation_info>

        <transcript>
        \(context)
        </transcript>
        """
    }

    private static let fullQuestionRules = """
    <rules>
    - Answer only from the transcript. Don't fill gaps about what was said with assumptions or outside \
    knowledge; general knowledge is fine only to explain a term the user asks about.
    - If the transcript doesn't contain the answer, say so plainly in the first sentence (e.g. "The \
    transcript doesn't mention a budget."), then mention the closest thing it does say, if anything. Never guess.
    - Cite the timestamp of each line you rely on, copied exactly, e.g. [12:34]. Quote short phrases in \
    their original language when the exact wording matters.
    - Answer in the language of the user's question, even if the conversation is in another language.
    - Lead with the direct answer, then supporting detail. Keep simple answers short; use Markdown lists \
    only when they help.
    - Speech recognition can mishear words and names, and speaker labels may be wrong. When the answer \
    depends on an unclear passage or on who said something, say how certain it is.
    </rules>
    """

    private static let compactQuestionRules = """
    Rules: answer only from the transcript and never guess. If it doesn't contain the answer, say so \
    plainly. Cite the timestamps of the lines you use, like [12:34]. Answer in the language of the \
    question. Be brief and direct. Speaker labels and recognized words may contain errors.
    """
}
