# Contributing to scrib3

Thanks for helping. A few rules keep this project honest and small.

## Ground rules

- **Never claim a capability you have not verified.** If an engine supports a
  locale but nobody tested transcription, say “untested”, not “supported”.
- **Keep transcription on-device.** Do not add uploads, telemetry, analytics,
  crash reporting, or account systems.
- **Engines produce timed words, not cues.** Cue rules and subtitle writers stay
  shared so every engine behaves the same.
- **Keep the core UI-free.** Anything testable belongs in `Scrib3Core`.
- **Prefer Apple frameworks and small dependencies.** WhisperKit is the only
  large dependency; weigh any addition carefully.
- **Test the edge cases.** Timestamps, empty input, long words, Unicode, and
  cancellation have all produced bugs before.

## Development

```sh
swift test          # unit tests
swift run scrib3    # run the app
```

Integration tests use the real Speech framework and are opt-in:

```sh
# Apple assets may download on first run.
SCRIB3_INTEGRATION=1 swift test --filter AppleSpeechIntegration

# Downloads a Core ML Whisper model. Use a small variant for a smoke test.
SCRIB3_WHISPER_INTEGRATION=1 SCRIB3_WHISPER_MODEL=openai_whisper-tiny \
  swift test --filter WhisperKitIntegration
```

The committed fixtures are short synthesized WAV files. They are enough to
prove the engine paths and timings, not to benchmark accuracy.

## Project layout

```text
Sources/Scrib3Core/      UI-free: engines, audio feeding, cue segmentation,
                         line wrapping, SRT/VTT/TXT writers, queue, naming
Sources/Scrib3App/       SwiftUI app, player, Finder service, app model
Tests/Scrib3CoreTests/   unit and opt-in integration tests
docs/                    subtitle rules, engine notes, limitations
Resources/               Info.plist, entitlements, icns
scripts/                 icon generation, packaging, notarization, DMG
```

## Changing subtitle behavior

1. Change the rule in `CueSegmenter` or `LineWrapper` only after a failing test
   describes the new behavior.
2. Update [`docs/SUBTITLE_RULES.md`](docs/SUBTITLE_RULES.md).
3. Run the generated invariant test; it must keep every word and every
   timestamp invariant.

## Adding or changing an engine

1. Implement `TranscriptionEngine` and return `TimedWord` values.
2. Add locale-mapping and word-mapping unit tests.
3. Add an opt-in integration test with a committed fixture.
4. Add license text to `THIRD_PARTY_NOTICES.txt` and make sure
   `scripts/package.sh` copies it into `Resources/licenses`.
5. Document the download size, cache folder, and offline behavior in
   [`docs/ENGINES.md`](docs/ENGINES.md).

## Pull requests

- Keep changes focused.
- Include a test for behavior changes.
- Update the docs when support or behavior changes.
- Write UI strings and documentation in English.
- Do not commit generated `dist/`, `.build/`, or model files.

## Release builds

Requires macOS 26, the Xcode command line tools, and a Developer ID
Application identity for distribution.

```sh
swift test
scripts/package.sh arm64 0.1.0 1      # Apple Silicon
scripts/package.sh x86_64 0.1.0 1     # Intel; same version/build number

# Optional disk image for drag-to-install.
scripts/make-dmg.sh arm64 0.1.0
```

Without `CODESIGN_IDENTITY`, packaging uses an ad-hoc signature and is marked
**not for distribution**. With an identity, it enables Hardened Runtime and a
secure timestamp:

```sh
CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
  scripts/package.sh arm64 0.1.0 1
```

### Notarization

Store notary credentials once:

```sh
xcrun notarytool store-credentials scrib3-profile \
  --apple-id "you@example.com" --team-id TEAMID --password "app-specific-pw"
```

Then, after packaging:

```sh
scripts/notarize.sh dist/scrib3-0.1.0-apple-silicon/scrib3.app
```

The script verifies the signature, submits, staples, checks Gatekeeper, and
rewrites the ZIP with its SHA-256 checksum. Publish that exact ZIP.

`scripts/verify-release.sh` checks the bundle identifier, versions, Finder
service message, architecture, rpaths, linked libraries, signature, and archive
checksum. Packaging runs it automatically in development mode; run it with the
`release` mode (default) after notarization.

There is no automatic updater in 0.1.0. Users download releases manually.

## License

By contributing, you agree that your contributions are licensed under the MIT
license in [`LICENSE`](LICENSE).
