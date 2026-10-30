import Foundation
import Testing
@testable import Scrib3Core

@Suite("TranscriptionPipeline")
struct TranscriptionPipelineTests {
    @Test func turnsEngineWordsIntoCues() async throws {
        let engine = StubEngine(words: [
            TimedWord(text: "Hello.", start: 0, end: 0.5),
            TimedWord(text: "Next", start: 0.7, end: 1.2),
        ])
        let pipeline = TranscriptionPipeline(engine: engine)

        let cues = try await pipeline.transcribe(
            file: URL(fileURLWithPath: "/tmp/example.wav"),
            locale: Locale(identifier: "en_US"),
            progress: { _ in }
        )

        #expect(cues.map(\.text) == ["Hello.", "Next"])
        #expect(cues[0].start.seconds == 0)
    }

    @Test func forwardsProgressFromTheEngine() async throws {
        let engine = StubEngine(words: [TimedWord(text: "Hi", start: 0, end: 1)])
        let pipeline = TranscriptionPipeline(engine: engine)
        let recorder = ProgressBox()

        _ = try await pipeline.transcribe(
            file: URL(fileURLWithPath: "/tmp/example.wav"),
            locale: Locale(identifier: "en_US"),
            progress: { recorder.append($0) }
        )

        #expect(recorder.values == [.transcribing(0), .transcribing(0.5), .transcribing(1)])
    }

    @Test func propagatesEngineErrors() async {
        let engine = StubEngine(error: .notAMediaFile("broken.mp4"))
        let pipeline = TranscriptionPipeline(engine: engine)

        await #expect(throws: TranscriptionError.notAMediaFile("broken.mp4")) {
            try await pipeline.transcribe(
                file: URL(fileURLWithPath: "/tmp/broken.mp4"),
                locale: Locale(identifier: "en_US"),
                progress: { _ in }
            )
        }
    }

    @Test func producesNoCuesForEmptySpeech() async throws {
        let engine = StubEngine(words: [])
        let pipeline = TranscriptionPipeline(engine: engine)
        let cues = try await pipeline.transcribe(
            file: URL(fileURLWithPath: "/tmp/silent.wav"),
            locale: Locale(identifier: "en_US"),
            progress: { _ in }
        )
        #expect(cues.isEmpty)
    }
}

private struct StubEngine: TranscriptionEngine {
    let identifier: EngineIdentifier = .apple
    let displayName = "Stub"
    var words: [TimedWord] = []
    var error: TranscriptionError?

    func supportedLocales() async throws -> [Locale] { [Locale(identifier: "en_US")] }
    func installedLocales() async throws -> [Locale] { [] }
    func prepare(
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws {}

    func transcribe(
        file: URL,
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws -> [TimedWord] {
        if let error { throw error }
        progress(.transcribing(0))
        progress(.transcribing(0.5))
        progress(.transcribing(1))
        return words
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [EngineProgress] = []

    func append(_ progress: EngineProgress) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(progress)
    }

    var values: [EngineProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
