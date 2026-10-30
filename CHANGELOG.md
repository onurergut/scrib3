# Changelog

## 0.1.0 — 2026-10-30

First release.

- Drag-and-drop queue for video and audio files.
- Apple Speech engine: `SpeechTranscriber`, with `DictationTranscriber` fallback
  for locales it does not cover, including Turkish.
- Optional WhisperKit engine with the Whisper large-v3 Core ML model.
- SRT, WebVTT, and TXT export with 42-character, two-line, seven-second cues.
- Review pane with player, click-to-seek cues, and inline text editing.
- Finder Quick Action: “Transcribe with scrib3”.
- On-device transcription with one-time model downloads and no telemetry.
