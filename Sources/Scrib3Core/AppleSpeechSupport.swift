import CoreMedia
import Foundation
import Speech

public extension Locale {
    /// Stable, case-insensitive key used to compare locales across frameworks.
    var bcp47Key: String {
        identifier(.bcp47).lowercased()
    }
}

public enum AppleTranscriberKind: Sendable, Equatable {
    /// General-purpose, punctuation-aware, recommended for long-form audio.
    case speechTranscriber
    /// Same models as on-device system dictation; covers more locales.
    case dictationTranscriber
}

public enum AppleLocaleSupport {
    /// `SpeechTranscriber` is preferred wherever it works. Apple documents
    /// `DictationTranscriber` as the fallback for other on-device locales.
    public static func preferredKind(
        for locale: Locale,
        speechLocales: [Locale],
        dictationLocales: [Locale]
    ) -> AppleTranscriberKind? {
        let key = locale.bcp47Key
        if speechLocales.contains(where: { $0.bcp47Key == key }) {
            return .speechTranscriber
        }
        if dictationLocales.contains(where: { $0.bcp47Key == key }) {
            return .dictationTranscriber
        }
        return nil
    }

    public static func merged(speech: [Locale], dictation: [Locale]) -> [Locale] {
        var seen = Set<String>()
        var result: [Locale] = []

        for locale in speech + dictation {
            if seen.insert(locale.bcp47Key).inserted {
                result.append(locale)
            }
        }
        return result
    }
}

enum SpeechTextReader {
    /// Converts the attributed text of one transcriber result into timed words.
    ///
    /// The Speech framework usually emits one run per word. Some locales emit
    /// punctuation as its own run without a duration; that punctuation belongs
    /// to the preceding word.
    static func words(from text: AttributedString) -> [TimedWord] {
        var words: [TimedWord] = []

        for run in text.runs {
            let raw = String(text[run.range].characters)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let isPunctuation = trimmed.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0)
                    || CharacterSet.symbols.contains($0)
            }

            if isPunctuation {
                guard let last = words.last else { continue }
                let end: Double
                if let range = run.audioTimeRange, range.isValid {
                    end = max(last.end, CMTimeRangeGetEnd(range).seconds)
                } else {
                    end = last.end
                }
                words[words.count - 1] = TimedWord(
                    text: last.text + trimmed,
                    start: last.start,
                    end: max(last.start, end),
                    confidence: last.confidence
                )
                continue
            }

            guard let range = run.audioTimeRange, range.isValid else { continue }
            let rawStart = range.start.seconds
            let rawEnd = CMTimeRangeGetEnd(range).seconds
            guard rawStart.isFinite, rawEnd.isFinite else { continue }
            let start = max(0, rawStart)
            let end = max(start, rawEnd)
            words.append(TimedWord(
                text: trimmed,
                start: start,
                end: end,
                confidence: run.transcriptionConfidence
            ))
        }

        return words
    }
}
