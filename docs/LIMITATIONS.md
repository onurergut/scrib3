# Known limitations

## Scope

- No speaker diarization. Cues are not labeled by speaker.
- No subtitle burn-in. scrib3 writes sidecar files; use a video tool to mux or
  burn them in.
- No translation. Subtitles are in the spoken language.
- No live microphone transcription. Files only.
- No cloud engines. All recognition is on-device.

## Accuracy

- Noisy rooms, music, overlapping speakers, reverberation, and strong accents
  reduce accuracy. This is a general speech-recognition limit, not a bug.
- Apple's `DictationTranscriber` fallback (used for Turkish) returns no
  punctuation or capitalization and splits results at roughly 60 seconds.
  WhisperKit is the better engine for Turkish subtitles.
- WhisperKit's large-v3 model is strong but still makes mistakes, especially on
  proper nouns and technical vocabulary.
- Always review the transcript before publishing.

## Models and network

- The first transcription in a language needs network access: macOS downloads
  Apple's asset, or WhisperKit downloads its 626 MB model.
- Apple's language asset list is runtime data. A locale shown by one macOS
  release may differ on another.
- If Apple removes or revokes an asset, `speech` transcription fails with a
  clear error; re-running with WhisperKit is the fallback.
- WhisperKit model files are stored outside the app and are not removed when the
  app is deleted.

## Hardware and OS

- macOS 26 or later is required because `SpeechAnalyzer` is a macOS 26 API.
- `SpeechTranscriber` has hardware requirements. On unsupported Macs the app's
  Apple engine can still use `DictationTranscriber` for many locales, including
  Turkish.
- Intel builds are provided because macOS 26 supports Intel. Speech hardware
  support varies; WhisperKit may be the practical engine there.
- WhisperKit full-file transcription loads the audio track into memory. A
  multi-hour recording needs a lot of free RAM.
- The first WhisperKit load specializes the Core ML model. This took several
  minutes on the test machine and is shown as “Preparing model…”; later loads
  are much faster.

## Subtitles

- Edited cue text is re-wrapped on export. Explicit line breaks entered by the
  user are not preserved.
- A single word longer than 42 characters is kept intact and overflows its line.
- A word longer than 7 seconds cannot be split; its cue keeps the full duration.
- TXT unwraps all cue lines into sentences separated by blank lines. It is not
  a timecoded format.
- Cue timing follows word timings from the engine. If the engine's timing is
  imprecise, the subtitle timing inherits that imprecision.

## App behavior

- The Finder Quick Action appears after the app has been launched once so macOS
  can register the service.
- Cancelling stops the current file and marks queued files as cancelled. They
  are not resumed automatically; add them again or retry failures.
- Cancelling during the very first WhisperKit model download stops the UI, but
  the download already in flight may finish in the background. WhisperKit stops
  decoding at the next check; a window already being decoded may finish first.
- WhisperKit keeps the model loaded after first use until the app quits, so
  memory stays higher after the first WhisperKit transcription.
- There is no automatic updater in 0.1.0. Releases are manual downloads.
- The interface is English. Transcripts follow the spoken language.
