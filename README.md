# Transkribe

A tiny Mac app that transcribes everything you give it, privately and on your Mac.

- **Drop any audio or video file** onto the window (or its Dock icon), paste it with ⌘V, or press ⌘O. Voice Memos, Zoom recordings, podcasts, `.m4a`, `.mp3`, `.wav`, `.mov`, `.mp4` and more all work.
- **Record** your microphone, your Mac's system audio (calls, meetings, videos), or both. The menu bar icon starts and stops recordings without opening the window.
- **Know who said what.** Speakers are detected automatically (Speaker 1, 2, 3…), tuned for real conversations and phone calls. In “Mic + System” mode you are always *Me*, which is the most reliable way to separate the two sides of a call. Rename speakers with a click and see how much each person talked. If detection is off, **Adjust** sets the number of people, right-clicking a speaker merges them into another, and right-clicking a paragraph changes its speaker.
- **Every language, auto-detected.** Turkish, English, and the ~100 languages Whisper supports. No settings.
- **Listen along.** The floating player's timeline shows who spoke when. During playback the current word lights up and the transcript follows. Click a timestamp to jump; Space plays and pauses.
- **Search** across all transcripts, with matches highlighted inline. Accents and Turkish ı/İ don't matter (`istanbul` finds “İstanbul”).
- **Copy or export** as text, Markdown, or subtitles (`.srt`), with speaker names.

Transcription runs locally with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (OpenAI Whisper large-v3 turbo, Core ML) and speaker detection with [FluidAudio](https://github.com/FluidInference/FluidAudio) (LS-EEND, CALLHOME variant). Runaway repetitions Whisper sometimes produces ("olunununun…") are removed automatically. Nothing leaves your Mac.

## Build & run

Requires macOS 14+ on Apple Silicon and Xcode 16+ (command line tools are enough).

```bash
scripts/build-app.sh            # → build/Transkribe.app
scripts/build-app.sh --install  # also copies it to /Applications
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

- `Sources/TranskribeCore`: data model, storage, search, formatting, audio decoding, transcription (`TranscriptionEngine`), speaker detection (`DiarizationEngine`, `SpeakerAssigner`), repetition cleanup (`RepetitionFilter`), recorders
- `Sources/Transkribe`: SwiftUI app (state in `AppModel`, playback in `PlayerController`, views in `Views/`). Uses Liquid Glass on macOS 26, with material fallbacks on 14–15.
