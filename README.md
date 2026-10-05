# Transkribe

A tiny Mac app that transcribes everything you give it, privately and on your Mac.

- **Drop any audio or video file** onto the window (or its Dock icon), paste it with ⌘V, or press ⌘O. Voice Memos, Zoom recordings, podcasts, `.m4a`, `.mp3`, `.wav`, `.mov`, `.mp4`, any length.
- **Record** your microphone, your Mac's system audio (calls, meetings, videos), or both, from the window or the menu bar. The conversation is transcribed **live, in batches, while you talk**. Batches never cut a sentence or leave a gap, and hours-long recordings or files use constant memory and resume after a quit.
- **Conversations read in order.** With Mic + System, both channels are transcribed separately, so overlapping speech is never lost. Long turns are split where the other person cut in, quick reactions ("Esatto!", "Aynen", "Haha") become tapbacks on the message they respond to, and speaker bleed is removed by comparing the two channels' sound.
- **Easy on your Mac.** Transcription runs at background priority and pauses on its own when the Mac is hot, in Low Power Mode, on low battery or busy, then picks up exactly where it stopped. Recording is never interrupted.
- **Read it like a chat.** Pick which speaker is you, and your words appear on the right like sent iMessages, with everyone else on the left. During playback the spoken word lights up. Double-click a bubble to play it, and right-click it to change its speaker.
- **Know who said what.** Speakers are detected automatically, tuned for real conversations and phone calls. Rename people, merge two voices, reassign a bubble, or tell the app how many people talked.
- **Summarize and ask.** One click writes a summary in the conversation's language: key points, decisions, action items with owners, open questions, and who said what. Every point links to the moment it was said. Or ask questions in a chat. Choose the model: Claude through your existing Claude Code login (no setup), Apple Intelligence on-device, or Claude with an API key.
- **Tuned for English, Turkish and Italian.** Each stretch is locked to one of the three, which avoids misdetections and Whisper's repetition loops; loops that still happen are re-transcribed automatically. Search covers every conversation, and accents and Turkish ı/İ don't matter.
- **Copy or export** as text, Markdown, or subtitles (`.srt`).

Transcription runs locally with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Whisper large-v3 turbo) and speaker detection with [FluidAudio](https://github.com/FluidInference/FluidAudio) (LS-EEND). Audio never leaves your Mac. Only the text you choose to summarize or ask about goes to the model you picked, and Apple Intelligence keeps even that on-device.

## Build & run

Requires macOS 14+ on Apple Silicon and Xcode 16+ (command line tools are enough).

```bash
scripts/build-app.sh            # → build/Transkribe.app
scripts/build-app.sh --install  # also copies it to /Applications
scripts/make-dmg.sh             # → build/Transkribe.dmg (drag-to-Applications installer)
open build/Transkribe.app
```

On first launch the app downloads the speech models (~640 MB) and optimizes them for your Mac. That takes a minute or two, happens once, and shows in the sidebar while it runs. After that it works offline.

### Permissions

- **Microphone**: asked the first time you record with the mic.
- **System audio**: macOS lists this under *Privacy & Security → Screen & System Audio Recording*. Only audio is captured; the screen isn't recorded.

The build is ad-hoc signed, so macOS may ask for these again after you rebuild.

## Where things live

| What | Where |
| --- | --- |
| Transcripts & audio | `~/Library/Application Support/Transkribe/Library/<id>/` |
| Speech model | `~/Library/Application Support/Transkribe/Models/` |

Each transcript is a folder with `transcript.json` and its audio. Delete a folder to remove it.

## Development

```bash
swift build
swift test                                                           # unit tests
TRANSKRIBE_INTEGRATION=1 swift test --filter TranscriptionIntegrationTests  # real models: Turkish, English, speakers
```

- `Sources/TranskribeCore`: data model, windowed pipeline (`Pipeline/`: `WindowPlanner`, `TrackTranscriber`, `PCMStore`), AI layer (`AI/`: providers, `Summarizer`, `Assistant`, `Prompts`), chat layout (`ChatLayout`),, storage, search, formatting, audio decoding, transcription (`TranscriptionEngine`), speaker detection (`DiarizationEngine`, `SpeakerAssigner`), repetition cleanup (`RepetitionFilter`), recorders
- `Sources/Transkribe`: SwiftUI app (state in `AppModel`, playback in `PlayerController`, views in `Views/`). Uses Liquid Glass on macOS 26, with material fallbacks on 14–15.
