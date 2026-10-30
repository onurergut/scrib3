import AVFoundation
import Foundation
import Testing
@testable import Scrib3Core

/// Downloads a Core ML Whisper model, so it is opt-in. `SCRIB3_WHISPER_MODEL`
/// may select a smaller variant for local smoke tests.
private let whisperIntegrationEnabled =
    ProcessInfo.processInfo.environment["SCRIB3_WHISPER_INTEGRATION"] == "1"

@Suite(
    "WhisperKit integration",
    .enabled(if: whisperIntegrationEnabled, "Set SCRIB3_WHISPER_INTEGRATION=1 to run")
)
struct WhisperKitIntegrationTests {
    private func fixture(_ name: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures")
        )
    }

    @Test func transcribesTurkishAudio() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib3-whisper-integration", isDirectory: true)
        let variant = ProcessInfo.processInfo.environment["SCRIB3_WHISPER_MODEL"]
            ?? "openai_whisper-tiny"
        let engine = WhisperKitEngine(downloadBase: base, modelVariant: variant)

        let locale = Locale(identifier: "tr_TR")
        let supported = try await engine.supportedLocales()
        #expect(supported.contains { $0.language.languageCode?.identifier == "tr" })

        let url = try fixture("turkish")
        let words = try await engine.transcribe(
            file: url,
            locale: locale,
            progress: { _ in }
        )

        #expect(!words.isEmpty)
        let rawText = words.map(\.text).joined(separator: " ")
        let text = rawText.lowercased()
        #expect(text.contains("merhaba"))

        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        for word in words {
            #expect(word.start >= 0)
            #expect(word.end >= word.start)
            #expect(word.end <= duration + 0.25)
        }
    }
}
