import AVFoundation
import Foundation
import Testing
@testable import Scrib3Core

/// These tests use the real Speech framework and may download language assets
/// on first run. They are opt-in so CI does not depend on network or hardware.
private let integrationEnabled = ProcessInfo.processInfo.environment["SCRIB3_INTEGRATION"] == "1"

@Suite(
    "Apple speech integration",
    .enabled(if: integrationEnabled, "Set SCRIB3_INTEGRATION=1 to run")
)
struct AppleSpeechIntegrationTests {
    private func fixture(_ name: String) throws -> URL {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures")
        )
        return url
    }

    private func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    @Test func listsTurkishAsASupportedLocale() async throws {
        let engine = AppleSpeechEngine()
        let locales = try await engine.supportedLocales()
        #expect(locales.contains { $0.bcp47Key == "tr-tr" })
        #expect(locales.contains { $0.bcp47Key == "en-us" })
    }

    @Test func transcribesTurkishWithDictationFallback() async throws {
        let url = try fixture("turkish")
        let engine = AppleSpeechEngine()
        let words = try await engine.transcribe(
            file: url,
            locale: Locale(identifier: "tr_TR"),
            progress: { _ in }
        )

        #expect(!words.isEmpty)
        let text = words.map(\.text).joined(separator: " ").lowercased()
        #expect(text.contains("merhaba"))
        #expect(text.contains("denemesi"))

        let mediaDuration = try duration(of: url)
        for word in words {
            #expect(word.start >= 0)
            #expect(word.end >= word.start)
            #expect(word.end <= mediaDuration + 0.25)
        }
    }

    @Test func transcribesEnglishWithSpeechTranscriber() async throws {
        let url = try fixture("english")
        let engine = AppleSpeechEngine()
        let words = try await engine.transcribe(
            file: url,
            locale: Locale(identifier: "en_US"),
            progress: { _ in }
        )

        #expect(!words.isEmpty)
        let text = words.map(\.text).joined(separator: " ")
        #expect(text.lowercased().contains("subtitle"))
        #expect(text.contains("."), "SpeechTranscriber should emit punctuation")

        let mediaDuration = try duration(of: url)
        for word in words {
            #expect(word.end >= word.start)
            #expect(word.end <= mediaDuration + 0.25)
        }
    }

    @Test func reportsProgressWhileTranscribing() async throws {
        let url = try fixture("english")
        let engine = AppleSpeechEngine()
        let recorder = ProgressRecorder()

        _ = try await engine.transcribe(
            file: url,
            locale: Locale(identifier: "en_US"),
            progress: { recorder.record($0) }
        )

        let fractions = recorder.transcriptionFractions
        #expect(!fractions.isEmpty)
        #expect(fractions.last ?? 0 >= 0.9)
        #expect(fractions == fractions.sorted())
    }

    @Test func rejectsUnsupportedLocale() async throws {
        let engine = AppleSpeechEngine()
        await #expect(throws: TranscriptionError.self) {
            try await engine.transcribe(
                file: try fixture("english"),
                locale: Locale(identifier: "is_IS"),
                progress: { _ in }
            )
        }
    }

    @Test func rejectsFileWithoutAudio() async throws {
        let engine = AppleSpeechEngine()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib3-empty-\(UUID().uuidString).wav")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: TranscriptionError.self) {
            try await engine.transcribe(
                file: url,
                locale: Locale(identifier: "en_US"),
                progress: { _ in }
            )
        }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [Double] = []

    func record(_ progress: EngineProgress) {
        guard progress.phase == .transcribing, let fraction = progress.fraction else { return }
        lock.lock()
        defer { lock.unlock() }
        fractions.append(fraction)
    }

    var transcriptionFractions: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return fractions
    }
}
