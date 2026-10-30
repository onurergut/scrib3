# Transcription engines

Both engines implement `TranscriptionEngine` in `Sources/Scrib3Core`. The
pipeline only sees timed words; cue rules and subtitle formats are shared.

```swift
public protocol TranscriptionEngine: Sendable {
    var identifier: EngineIdentifier { get }
    var displayName: String { get }

    func supportedLocales() async throws -> [Locale]
    func installedLocales() async throws -> [Locale]
    func prepare(locale: Locale,
                 progress: @escaping @Sendable (EngineProgress) -> Void) async throws
    func transcribe(file: URL, locale: Locale,
                    progress: @escaping @Sendable (EngineProgress) -> Void) async throws
        -> [TimedWord]
}
```

Cancelling the calling task must stop the engine. `progress` may be called from
any thread and reports either `.downloading` or `.transcribing` with an optional
fraction.

## Apple Speech

`AppleSpeechEngine` uses Apple's on-device Speech framework (`SpeechAnalyzer`),
available from macOS 26.

- It asks `SpeechTranscriber.supportedLocale(equivalentTo:)` first. That module
  is Apple's general-purpose, long-form transcriber and produces punctuation.
- If `SpeechTranscriber` does not support the locale, the engine asks
  `DictationTranscriber.supportedLocale(equivalentTo:)`. Apple documents this as
  the fallback for locales covered by system dictation models.
- Unsupported locales fail before any file is read.

### Verified behavior (macOS 27.0.1, Xcode 27.1)

- `SpeechTranscriber.supportedLocales`: 45 locales. **Turkish is not among
  them**; `supportedLocale(equivalentTo: tr_TR)` returns `nil`.
- `DictationTranscriber.supportedLocales`: 54 locales, including `tr_TR`.
- Turkish sample transcribed correctly with the Dictation fallback, with
  word-level time ranges and confidence, but without punctuation or
  capitalization. Results are chunked at about 60 seconds.
- English sample transcribed with `SpeechTranscriber` including punctuation and
  word-level runs.
- AAC audio inside an MP4 file at 44.1 kHz was read by `AVAudioFile` and
  converted by the engine to the analyzer format without a separate extraction
  step.
- A 3-minute file produced three 60-second results with global timestamps.

These lists are runtime values and can change with macOS updates. The app always
reads them from the framework.

### Model assets

`AssetInventory` manages Apple's assets:

1. `AssetInventory.status(forModules:)` reports `unsupported`, `downloading`,
   `supported`, or `installed`.
2. `AssetInventory.assetInstallationRequest(supporting:)` returns `nil` when
   nothing needs downloading.
3. `request.progress` is coarse: measured total was one unit, with fractions
   jumping roughly 0 → 0.2 → 0.57 → 0.88 → 1.0 for English.
4. `request.downloadAndInstall()` performs the download.

Assets persist between launches, are shared between apps, live outside the app
bundle and outside app memory, and are updated by the system. The app may hold
up to `AssetInventory.maximumReservedLocales` (5) locale reservations; scrib3
does not reserve additional locales explicitly.

Measured English install time on a fast connection: about 11 seconds.

### Audio path

The engine reads one-second chunks with `AVAudioFile`, converts to
`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` with
`AVAudioConverter`, and feeds an `AsyncStream<AnalyzerInput>` to the analyzer.
Progress is the fraction of source frames consumed. Task cancellation calls
`cancelAndFinishNow()` and stops the feeder.

## WhisperKit

`WhisperKitEngine` wraps the MIT-licensed
[WhisperKit](https://github.com/argmaxinc/WhisperKit) package with the
multilingual Whisper large-v3 Core ML model.

- Model variant: `large-v3-v20240930_626MB` (about 626 MB).
- Download: one time, from `argmaxinc/whisperkit-coreml` on Hugging Face, into
  `~/Library/Application Support/scrib3/Models`.
- Offline detection checks the local Hugging Face cache for
  `AudioEncoder.mlmodelc` before touching the network.
- Word timings come from `TranscriptionResult.allWords` with
  `wordTimestamps: true`.
- The language is passed explicitly; a locale whose language code is not in
  Whisper's language table is rejected before loading or downloading anything.
- Turkish output was verified to include capitalization and punctuation:
  `Merhaba, bu bir alt yazı denemesidir.`

WhisperKit loads the full audio into memory for full-file transcription. This is
the main memory cost for very long recordings. The first load in a new process
also triggers Core ML specialization; measured time was several minutes for
large-v3 on macOS 27, while subsequent loads were fast. The UI shows
“Preparing model…” during this phase.

## Adding a third engine

1. Implement `TranscriptionEngine`. Return `TimedWord` values from the engine;
   do not build subtitle cues.
2. Add a case to `EngineIdentifier` and a label in the app's engine picker.
3. Keep model downloads behind `prepare(locale:progress:)` and report fractions
   when the backend exposes them.
4. Add unit tests for locale mapping and word mapping, plus an opt-in
   integration test with a committed fixture.
5. Add the license and notice to `THIRD_PARTY_NOTICES.txt` and to the packaged
   `Resources/licenses` folder.
