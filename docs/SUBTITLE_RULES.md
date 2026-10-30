# Subtitle rules

scrib3 converts word-level timings into cues before writing any subtitle
format. The rules are implemented in `CueSegmenter` and `LineWrapper` and
covered by unit tests, including a generated invariant test.

## Cue limits

| Rule | Value |
|---|---|
| Maximum lines per cue | 2 |
| Maximum characters per line | 42 |
| Maximum cue duration | 7 seconds |
| Minimum cue duration | 0.8 seconds |
| Pause that ends a sentence | 0.6 seconds |
| Gap kept before the next cue | 0.05 seconds |

The limits are `SegmentationRules.standard`. They can be changed in code
without touching an engine or a subtitle writer.

## Grouping

1. Words are trimmed, empty words are dropped, and the stream is sorted by
   start time.
2. Words become sentences. A sentence ends when the word ends with `.`, `!`,
   `?`, or `…` (also when the punctuation is followed by a closing quote or
   bracket), or when the gap before the next word is at least 0.6 seconds.
3. Sentences are never merged. A cue boundary therefore never falls inside a
   sentence unless a limit forces it.
4. A sentence is split greedily into the largest cues that satisfy the
   duration, character, and line limits. When a split is forced, the segmenter
   looks for a pause of at least 0.25 seconds that stands out from the other
   gaps and breaks there instead of at the hard limit.
5. A single word that cannot fit (very long word, or a word longer than seven
   seconds) still gets its own cue. The alternative would be losing text.
6. Short cues are extended to 0.8 seconds, but never past 0.05 seconds before
   the next cue.

## Line wrapping

`LineWrapper` joins the cue words with single spaces. If the text fits in 42
characters it stays on one line. Otherwise it chooses the word boundary that
minimizes the difference in length between the two lines, preferring a boundary
right after sentence punctuation when the difference ties. Words are never
split. A single word longer than 42 characters keeps its own line and
overflows.

Line wrapping is applied when cues are produced and again when edited cues are
exported. Edited text is stored without explicit line breaks.

## Timing

- Cue start is the first word's start.
- Cue end is the last word's end.
- Times are stored as whole milliseconds, rounded once from the engine output.
- Negative times are clamped to zero.
- Subtitle timestamps use `HH:MM:SS,mmm` for SRT and `HH:MM:SS.mmm` for WebVTT.
  Hours are not truncated at 99.

## Output formats

- **SRT:** one-based index, blank line between cues, LF line endings, UTF-8.
- **WebVTT:** `WEBVTT` header, no cue identifiers, dot separator for
  milliseconds.
- **TXT:** cue text only, soft line breaks unwrapped to spaces, blank line
  between cues.

Writers normalize CRLF and trim leading/trailing blank lines from cue text.
They do not rewrite words.
