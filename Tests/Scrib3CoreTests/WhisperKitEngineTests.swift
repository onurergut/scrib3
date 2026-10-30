import Foundation
import Testing
import WhisperKit
@testable import Scrib3Core

@Suite("WhisperKit engine")
struct WhisperKitEngineTests {
    @Test func listsWhisperLanguagesIncludingTurkish() async throws {
        let engine = WhisperKitEngine()
        let locales = try await engine.supportedLocales()
        #expect(locales.contains { $0.language.languageCode?.identifier == "tr" })
        #expect(locales.contains { $0.language.languageCode?.identifier == "en" })
        #expect(locales.count > 90)
    }

    @Test func mapsLocalesToWhisperLanguageCodes() {
        #expect(WhisperLanguage.code(for: Locale(identifier: "tr_TR")) == "tr")
        #expect(WhisperLanguage.code(for: Locale(identifier: "en_US")) == "en")
        #expect(WhisperLanguage.code(for: Locale(identifier: "de_DE")) == "de")
        #expect(WhisperLanguage.code(for: Locale(identifier: "tlh")) == nil)
    }

    @Test func trimsWhisperWordsAndCarriesConfidence() {
        let words = WhisperWordMapper.words(from: [
            WordTiming(word: " merhaba", tokens: [], start: 0.5, end: 1.0, probability: 0.9),
            WordTiming(word: " dünya.", tokens: [], start: 1.0, end: 1.6, probability: 0.8),
        ])
        #expect(words.map(\.text) == ["merhaba", "dünya."])
        #expect(abs(words[0].start - 0.5) < 0.0001)
        #expect(abs(words[0].end - 1.0) < 0.0001)
        #expect(abs(words[1].start - 1.0) < 0.0001)
        #expect(abs(words[1].end - 1.6) < 0.0001)
        #expect(words[0].confidence == Double(Float(0.9)))
        #expect(words[1].confidence == Double(Float(0.8)))
    }

    @Test func dropsBlankWhisperWordsAndClampsTimes() {
        let words = WhisperWordMapper.words(from: [
            WordTiming(word: "  ", tokens: [], start: 0, end: 0.1, probability: 1),
            WordTiming(word: "odd", tokens: [], start: -1, end: -0.5, probability: 1),
            WordTiming(word: "inverted", tokens: [], start: 2, end: 1, probability: 1),
        ])
        #expect(words.map(\.text) == ["odd", "inverted"])
        #expect(words.allSatisfy { $0.start >= 0 && $0.end >= $0.start })
    }

    @Test func rejectsUnsupportedLocaleBeforeDownloading() async {
        let engine = WhisperKitEngine(
            downloadBase: FileManager.default.temporaryDirectory
                .appendingPathComponent("scrib3-whisper-tests", isDirectory: true)
        )
        await #expect(throws: TranscriptionError.self) {
            try await engine.transcribe(
                file: URL(fileURLWithPath: "/tmp/does-not-exist.wav"),
                locale: Locale(identifier: "tlh"),
                progress: { _ in }
            )
        }
    }
}
