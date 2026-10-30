<div align="center">
  <img src="docs/icon.png" width="112" alt="scrib3 app icon">
  <h1>scrib3</h1>
  <p><b>Turn video and audio files into SRT, VTT, or TXT subtitles — on your Mac.</b></p>

  <p>
    <a href="https://github.com/onurergut/scrib3/actions/workflows/ci.yml"><img src="https://github.com/onurergut/scrib3/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status"></a>
    <a href="https://github.com/onurergut/scrib3/releases/latest"><img src="https://img.shields.io/github/v/release/onurergut/scrib3?label=release" alt="Latest release"></a>
    <img src="https://img.shields.io/badge/macOS-26%2B-blue" alt="macOS 26 or later">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license">
  </p>
</div>

**Status:** actively developed. Latest release: **0.1.0** (30 October 2026).

scrib3 is a native SwiftUI app that transcribes the audio track of a video or
audio file and writes a timed subtitle file. Drag files in, choose a language,
review the cues next to a player, fix the text, then export. Speech recognition
runs on-device; recordings are never uploaded.

> [!IMPORTANT]
> The first transcription in a language downloads that engine's model once.
> Apple's model is managed by macOS; WhisperKit downloads 626 MB from Hugging
> Face. After that, transcription works offline.

## Why scrib3

- **macOS dictation** can type what it hears, but it does not produce subtitle
  files, respect cue line and duration limits, or let you review timed text
  beside the video.
- **Online transcription services** upload your recordings and usually charge
  per minute. scrib3 reads the file where it is.
- **Whisper command-line setups** are scriptable and excellent for automation.
  scrib3 is for interactive work: drag, transcribe, click a cue, fix it, export.
- **Subtitle editors** assume a transcript already exists. scrib3 does the
  transcription and the subtitle shaping in one app.

**When not to use scrib3:** you need speaker labels, burned-in subtitles,
translation, live microphone input, or a legal-grade transcript. Noisy rooms,
music, crosstalk, and strong accents reduce accuracy, and every result needs a
human review. It also needs macOS 26 and network access for the first model
download.

## Install

1. Open the [releases page](https://github.com/onurergut/scrib3/releases) and
   download the build for your Mac:
   - **Apple Silicon:** `scrib3-0.1.0-apple-silicon.zip`
   - **Intel:** `scrib3-0.1.0-intel.zip`
2. Unzip, drag **scrib3** to Applications, and open it. Releases are Developer
   ID-signed, notarized, and stapled.

Each ZIP has a matching `.sha256` file if you want to verify the download:

```sh
shasum -a 256 -c scrib3-0.1.0-apple-silicon.zip.sha256
```

**Requirements:** macOS 26 or later. No Homebrew, account, or runtime install is
needed.

## Use

1. Drop video or audio files onto the window, or press **Add Files…** (⌘O).
   MP4, MOV, M4A, MP3, WAV, and other formats AVFoundation can read are
   accepted.
2. Choose a **language** and an **engine**. The language list is read from the
   selected engine at runtime.
3. The queue transcribes one file at a time and shows progress per file.
   **Cancel** stops the queue; **Retry failed** re-runs only failures.
4. Click a finished file to open the review pane. Click a cue timestamp to seek
   the player, and edit cue text in place.
5. **Export** writes SRT, VTT, or TXT for the selected file. **Export all**
   writes one file per finished item into a folder you choose.

**Finder:** right-click selected video or audio files →
**Quick Actions → Transcribe with scrib3**. The action appears after the app has
been launched once.

## Engines

Both engines sit behind the same `TranscriptionEngine` protocol, so subtitle
rules and exports are identical.

| Engine | Model | One-time download | Highlights |
|---|---|---|---|
| **Apple Speech** (default) | `SpeechTranscriber`, with `DictationTranscriber` fallback | Managed by macOS | Long-form audio, 45 `SpeechTranscriber` locales plus the dictation list, no third-party runtime |
| **WhisperKit** | OpenAI Whisper large-v3, Core ML | 626 MB from Hugging Face | Turkish punctuation and capitalization, 99 languages |

Apple's `SpeechTranscriber` does not support Turkish. scrib3 falls back to
`DictationTranscriber`, which transcribes Turkish accurately but returns
lowercase text without punctuation in roughly 60-second chunks. Choose
WhisperKit when punctuation and casing matter for Turkish subtitles.

Model assets live outside the app bundle and survive app updates. Apple's assets
are shared between apps and managed by the system; WhisperKit's model is cached
in `~/Library/Application Support/scrib3/Models`. Details and the protocol are in
[`docs/ENGINES.md`](docs/ENGINES.md).

## Subtitles

scrib3 does not save raw recognizer output. Cues follow ordinary subtitle limits:

- at most **2 lines** per cue and about **42 characters** per line,
- at most **7 seconds** per cue,
- breaks at sentence punctuation or pauses, never inside a word,
- a readable minimum duration without overlapping the next cue.

Wrapping is applied again on export, so edited text follows the same rules. The
exact algorithm and edge cases are in
[`docs/SUBTITLE_RULES.md`](docs/SUBTITLE_RULES.md).

## Privacy

Files are read on this Mac and never uploaded. There is no telemetry, analytics,
crash reporting, account, or system-profile upload.

Network access is used only for model downloads: Apple's speech assets from
Apple's servers, or the WhisperKit model from Hugging Face. Those services see
ordinary connection metadata such as your IP address.

## Known limitations

> [!WARNING]
> Accuracy is not guaranteed. Review every transcript before publishing, and do
> not rely on scrib3 for legal, medical, or safety-critical records.

- **No diarization.** Speakers are not labeled.
- **No burn-in, translation, or live microphone input.**
- **Apple's Turkish fallback has no punctuation or capitalization.**
- **WhisperKit loads the audio track into memory.** Very long recordings need
  corresponding free RAM. The first load also specializes the Core ML model;
  measured time was several minutes, and later loads are much faster.
- **First use needs network access** for the selected engine's model.
- **Cancellation** stops the current file, but a WhisperKit model download
  already in flight may finish in the background.
- **Intel Macs** run scrib3 on macOS 26, but `SpeechTranscriber` hardware support
  varies; the dictation fallback covers more devices.
- **Automated input coverage** is WAV plus a manual MP4/AAC probe. Other
  AVFoundation formats use the same path but are not each covered by a fixture.
- **No automatic updater in 0.1.0.** Releases are manual downloads.

The longer list is in [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md).

## Build from source

Requires Xcode 26 or later (macOS 26 SDK) and the Xcode command line tools.

```sh
swift test                 # unit tests
swift run scrib3           # run the app
```

Integration tests use the real Speech framework and may download models:

```sh
SCRIB3_INTEGRATION=1 swift test --filter AppleSpeechIntegration

SCRIB3_WHISPER_INTEGRATION=1 SCRIB3_WHISPER_MODEL=openai_whisper-tiny \
  swift test --filter WhisperKitIntegration
```

Packaging, signing, notarization, and the release workflow are documented in
[`CONTRIBUTING.md`](CONTRIBUTING.md#release-builds).

## Documentation

- [Engine behavior and model downloads](docs/ENGINES.md)
- [Subtitle rules](docs/SUBTITLE_RULES.md)
- [Known limitations](docs/LIMITATIONS.md)

MIT licensed. WhisperKit is MIT; swift-argument-parser is Apache 2.0 with the
Runtime Library Exception. See [`THIRD_PARTY_NOTICES.txt`](THIRD_PARTY_NOTICES.txt).
