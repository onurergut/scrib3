# scrib3 project guide

A native macOS app that transcribes the audio track of a video or audio file
on-device and writes SRT, VTT, or TXT subtitles. SwiftUI, Swift 6 strict
concurrency, SwiftPM, macOS 26 or later.

Read `README.md` for the user-facing story, `CONTRIBUTING.md` for the release
process, and `docs/` for engine and subtitle details. This file is the short
version for day-to-day work.

## Commands

```sh
swift test                 # unit tests
swift run scrib3           # run the app

# Real Speech framework; may download Apple language assets.
SCRIB3_INTEGRATION=1 swift test --filter AppleSpeechIntegration

# Core ML model download; use a small variant for a smoke test.
SCRIB3_WHISPER_INTEGRATION=1 SCRIB3_WHISPER_MODEL=openai_whisper-tiny \
  swift test --filter WhisperKitIntegration

swift scripts/make-icon.swift   # regenerate Resources/scrib3.icns and docs/icon.png
```

Packaging and notarization are release-only. See `CONTRIBUTING.md` rather than
running them during a normal change:

```sh
CODESIGN_IDENTITY="Developer ID Application: ..." \
  scripts/package.sh arm64 0.1.0 <build-number>
NOTARY_PROFILE=<profile> scripts/notarize.sh dist/scrib3-0.1.0-apple-silicon/scrib3.app
scripts/verify-release.sh dist/scrib3-0.1.0-apple-silicon/scrib3.app 0.1.0 arm64 release <build-number>
```

## Layout

```text
Sources/Scrib3Core/   UI-free: engines, audio feeding, cue segmentation,
                      line wrapping, SRT/VTT/TXT writers, queue, naming
Sources/Scrib3App/    SwiftUI app, player, AppModel, Finder service
Tests/Scrib3CoreTests/ unit tests and opt-in integration tests
Tests/Scrib3AppTests/  app-level locale option tests
docs/                 engine notes, subtitle rules, limitations
Resources/            Info.plist, entitlements, generated icns
scripts/              icon, packaging, notarization, DMG, release verification
```

## Architecture rules

- **Engines return timed words, never cues.** `TranscriptionEngine` produces
  `[TimedWord]`; `CueSegmenter` is the only place that turns words into cues.
  This is what keeps Apple Speech and WhisperKit behavior identical.
- **Core stays UI-free.** Anything testable belongs in `Scrib3Core`. The app
  layer owns SwiftUI, AVKit, panels, and the Finder service.
- **Cancellation is part of the protocol.** Cancelling the calling task must
  stop the engine. Apple calls `cancelAndFinishNow()`; WhisperKit checks the
  callback between windows.
- **Progress is optional but honest.** Report `.downloading` and `.transcribing`
  with a fraction when available; otherwise pass `nil` and show an indeterminate
  state. Do not invent percentages.
- **Model access goes through `prepare(locale:progress:)`.** Never download or
  load a model as a side effect of constructing an engine.

## Non-obvious behavior

- **Turkish:** `SpeechTranscriber` does not support it. The Apple engine falls
  back to `DictationTranscriber`, which transcribes accurately but returns
  lowercase, unpunctuated text in roughly 60-second chunks. WhisperKit is the
  documented choice when punctuation/casing matters.
- **Apple assets:** `AssetInventory` status is `unsupported`, `downloading`,
  `supported`, or `installed`. `assetInstallationRequest` returns `nil` when no
  download is needed. Progress is coarse (one unit in tests), assets live
  outside the app bundle, are shared between apps, and the reservation limit is
  five locales.
- **WhisperKit:** the model is ~626 MB, cached in
  `~/Library/Application Support/scrib3/Models`, downloaded from Hugging Face
  once. The first load specializes Core ML and can take minutes; later loads
  are fast. Full-file transcription loads audio into memory.
- **System language:** use `SystemLanguage.preferredLocale`, not
  `Locale.current`. A SwiftPM app bundle with `CFBundleDevelopmentRegion=en`
  can make `Locale.current` resolve to English instead of the system language.
- **Single window:** use `Window`, not `WindowGroup`; Quick Action opens must
  reuse one window.
- **Audio path:** `AVAudioFile` reads MP4/M4A/WAV and feeds one-second chunks
  through `AVAudioConverter` to the analyzer format. A separate extraction step
  is not required for the tested MP4/AAC path. WAV is the automated fixture;
  other formats share the path but are not each covered.
- **Editing:** cue text is stored single-line in the app. Line wrapping is
  applied again at export with `LineWrapper`. Do not preserve user-entered
  newlines in exported cues.
- **Subtitle limits:** 42 characters per line, 2 lines, 7 seconds per cue, 0.8
  seconds minimum, 0.6-second sentence pause. Single long words and single
  words over seven seconds are allowed to overflow; document the exception
  instead of dropping text.
- **Hosted CI** does not expose the Speech language assets. The Apple Speech
  integration job is gated behind the `SPEECH_INTEGRATION` repository variable;
  run the suite locally instead. Do not make that job required.

## Testing rules

- Write the failing test first for core behavior: segmentation, wrapping,
  timestamp formatting, queue transitions, engine word mapping, export naming.
- Integration tests use the committed TTS fixtures. They prove engine paths and
  timing, not accuracy. Do not describe them as accuracy benchmarks.
- Keep tests deterministic. The segmenter has a generated invariant test; new
  rules must keep every word and preserve monotonic cue times.
- Swift Testing (`import Testing`, `@Test`, `#expect`) is the test framework.

## Claims and docs

- Never claim a capability that is not verified. If a locale or format was not
  exercised, say “untested”, not “supported”.
- Update `docs/ENGINES.md`, `docs/SUBTITLE_RULES.md`, or
  `docs/LIMITATIONS.md` when behavior or support changes.
- UI strings and documentation are English.
- There is no diarization, burn-in, translation, live microphone input, or
  cloud engine in this product.

## Security and privacy

- Files stay on the Mac. Do not add uploads, telemetry, analytics, crash
  reporting, accounts, or system-profile upload.
- Network use is limited to one-time model downloads (Apple assets or
  WhisperKit from Hugging Face).
- Never commit secrets, `.p12` files, model weights, `dist/`, or `build/`.
- Never print secret values in logs, tests, or documentation.
- Signing secrets live in the `release` GitHub environment, not repository
  scope. The release job requires environment approval.
- Do not add Claude/Co-Authored-By attribution lines to commits. The user
  explicitly asked for clean commit messages.
- Commit author email is the GitHub noreply address
  `143835250+onurergut@users.noreply.github.com`.

## Git and release workflow

- `main` is protected: pull request required, status checks required, force
  push and deletion disabled, rules apply to admins, conversations must be
  resolved.
- Required checks: `Build and unit tests`, `Package arm64`,
  `Package x86_64`. The Apple Speech integration check is intentionally not
  required.
- Work on a branch and open a PR. Do not try to push directly to `main`.
- Releases are driven by a `vX.Y.Z` tag (or manual dispatch). The tag version
  is passed to `package.sh`; the build number is the workflow run number.
- Release steps: build both architectures, Developer ID sign with Hardened
  Runtime, notarize, staple, verify, publish. Checksum files use
  `shasum`'s `digest  filename` format so `shasum -a 256 -c` works.
- `RELEASE_AUTOMATION=true` and the six environment secrets enable the release
  workflow. Without them the job is skipped rather than failing.
- The Developer ID certificate expires periodically; rotate
  `DEVELOPER_ID_APPLICATION_P12` and its password before expiry.
- Dependabot updates both Swift packages and GitHub Actions. Actions are pinned
  to commit SHAs; review major-version bumps instead of merging blindly.

## Third-party

- WhisperKit 1.1.1 (MIT), pinned exactly in `Package.swift`.
- swift-argument-parser (Apache 2.0 with Runtime Library Exception), transitive.
- Whisper large-v3 weights are downloaded at runtime, not bundled. See
  `THIRD_PARTY_NOTICES.txt` and the packaged `Resources/licenses/` folder.
