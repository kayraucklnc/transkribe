# Transkribe

A tiny Mac app that transcribes everything you give it, privately and on your Mac.

- **Drop any audio or video file** onto the window (or its Dock icon), paste it with ⌘V, or press ⌘O. Voice Memos, Zoom recordings, podcasts, `.m4a`, `.mp3`, `.wav`, `.mov`, `.mp4` and more all work.
- **Record** your microphone, your Mac's system audio (calls, meetings, videos), or both. In “Mic + System” mode each side is labeled (*Me* / *Others*).
- **Every language, auto-detected.** Turkish, English, and the ~100 languages Whisper supports. No settings.
- **Click any timestamp** to hear that moment. Search across all transcripts. Accents and Turkish ı/İ don't matter (`istanbul` finds “İstanbul”).
- **Copy or export** as text, Markdown, or subtitles (`.srt`).

Transcription runs locally with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (OpenAI Whisper large-v3 turbo, Core ML). Nothing leaves your Mac.

## Build & run

Requires macOS 14+ on Apple Silicon and Xcode 16+ (command line tools are enough).

```bash
scripts/build-app.sh            # → build/Transkribe.app
scripts/build-app.sh --install  # also copies it to /Applications
open build/Transkribe.app
```

On first launch the app downloads the speech model (~630 MB) and optimizes it for your Mac. That takes a minute or two, happens once, and shows in the sidebar while it runs. After that it works offline.

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
TRANSKRIBE_INTEGRATION=1 swift test --filter TranscriptionIntegrationTests  # real model, Turkish + English
```

- `Sources/TranskribeCore`: model, storage, search, formatting, audio decoding, WhisperKit engine, recorders
- `Sources/Transkribe`: SwiftUI app (state in `AppModel`, playback in `PlayerController`)
