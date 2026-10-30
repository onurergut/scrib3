import CoreMedia
import Foundation
import Speech
import Testing
@testable import Scrib3Core

@Suite("Apple speech locale support")
struct AppleSpeechSupportTests {
    private let turkish = Locale(identifier: "tr_TR")
    private let englishUS = Locale(identifier: "en_US")

    @Test func prefersSpeechTranscriberWhenItSupportsTheLocale() {
        let kind = AppleLocaleSupport.preferredKind(
            for: englishUS,
            speechLocales: [englishUS],
            dictationLocales: [englishUS, turkish]
        )
        #expect(kind == .speechTranscriber)
    }

    @Test func fallsBackToDictationTranscriberForTurkish() {
        let kind = AppleLocaleSupport.preferredKind(
            for: turkish,
            speechLocales: [englishUS],
            dictationLocales: [englishUS, turkish]
        )
        #expect(kind == .dictationTranscriber)
    }

    @Test func returnsNilForUnsupportedLocale() {
        let kind = AppleLocaleSupport.preferredKind(
            for: Locale(identifier: "is_IS"),
            speechLocales: [englishUS],
            dictationLocales: [turkish]
        )
        #expect(kind == nil)
    }

    @Test func matchesLocaleRegardlessOfSeparatorOrRegionCase() {
        let kind = AppleLocaleSupport.preferredKind(
            for: Locale(identifier: "tr-TR"),
            speechLocales: [],
            dictationLocales: [Locale(identifier: "tr_TR")]
        )
        #expect(kind == .dictationTranscriber)
    }

    @Test func mergesLocalesWithoutDuplicatesPreservingSpeechFirst() {
        let merged = AppleLocaleSupport.merged(
            speech: [englishUS, Locale(identifier: "de_DE")],
            dictation: [englishUS, turkish]
        )
        #expect(merged.map(\.bcp47Key) == ["en-us", "de-de", "tr-tr"])
    }

    @Test func exposesBareLocaleNames() {
        #expect(turkish.language.languageCode?.identifier == "tr")
    }
}

@Suite("Speech attributed text reader")
struct SpeechTextReaderTests {
    private func timed(_ text: String, _ start: Double, _ end: Double) -> AttributedString {
        var piece = AttributedString(text)
        piece.audioTimeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 1000),
            end: CMTime(seconds: end, preferredTimescale: 1000)
        )
        return piece
    }

    private func combined(_ pieces: [AttributedString]) -> AttributedString {
        pieces.reduce(into: AttributedString()) { result, piece in
            result.append(piece)
        }
    }

    @Test func readsAudiotimeRangesAsTimedWords() {
        let text = combined([
            timed("Hello", 0, 0.5),
            timed(" there", 0.5, 1.0),
        ])
        let words = SpeechTextReader.words(from: text)
        #expect(words == [
            TimedWord(text: "Hello", start: 0, end: 0.5),
            TimedWord(text: "there", start: 0.5, end: 1.0),
        ])
    }

    @Test func attachesStandalonePunctuationToThePreviousWord() {
        let text = combined([
            timed("Hello", 0, 0.5),
            timed(" there", 0.5, 1.0),
            timed(".", 1.0, 1.0),
        ])
        let words = SpeechTextReader.words(from: text)
        #expect(words.map(\.text) == ["Hello", "there."])
    }

    @Test func dropsLeadingPunctuationWithoutAPreviousWord() {
        let text = combined([
            timed(".", 0, 0),
            timed("Hello", 0.1, 0.5),
        ])
        #expect(SpeechTextReader.words(from: text).map(\.text) == ["Hello"])
    }

    @Test func skipsWhitespaceOnlyRuns() {
        let text = combined([
            timed("  ", 0, 0.1),
            timed("Hello", 0.1, 0.5),
            timed("   ", 0.5, 0.6),
        ])
        #expect(SpeechTextReader.words(from: text).map(\.text) == ["Hello"])
    }

    @Test func carriesConfidenceThrough() {
        var piece = AttributedString("Hello")
        piece.audioTimeRange = CMTimeRange(
            start: .zero,
            end: CMTime(seconds: 0.5, preferredTimescale: 1000)
        )
        piece.transcriptionConfidence = 0.87

        let words = SpeechTextReader.words(from: piece)
        #expect(words.count == 1)
        #expect(words[0].confidence == 0.87)
    }

    @Test func ignoresRunsWithoutATimeRange() {
        let text = combined([
            AttributedString("untimed "),
            timed("Hello", 0, 0.5),
        ])
        #expect(SpeechTextReader.words(from: text).map(\.text) == ["Hello"])
    }

    @Test func skipsInvalidRanges() {
        let piece = timed("odd", 2, 1)
        #expect(SpeechTextReader.words(from: piece).isEmpty)
    }
}
