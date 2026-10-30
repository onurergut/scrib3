import Foundation
import Scrib3Core

/// Lets the queue keep a stable executor while the selected engine changes.
actor EngineRouter {
    private var engine: any TranscriptionEngine

    init(engine: any TranscriptionEngine) {
        self.engine = engine
    }

    func setEngine(_ engine: any TranscriptionEngine) {
        self.engine = engine
    }

    func transcribe(
        file: URL,
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws -> [SubtitleCue] {
        try await TranscriptionPipeline(engine: engine).transcribe(
            file: file,
            locale: locale,
            progress: progress
        )
    }
}
