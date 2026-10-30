import Foundation

/// Connects a transcription engine to cue segmentation. This is the only
/// place where words become subtitle cues, so every engine gets identical
/// subtitle behavior.
public struct TranscriptionPipeline: Sendable {
    public let engine: any TranscriptionEngine
    public let segmenter: CueSegmenter

    public init(
        engine: any TranscriptionEngine,
        segmenter: CueSegmenter = CueSegmenter()
    ) {
        self.engine = engine
        self.segmenter = segmenter
    }

    public func transcribe(
        file: URL,
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws -> [SubtitleCue] {
        let words = try await engine.transcribe(
            file: file,
            locale: locale,
            progress: progress
        )
        return segmenter.segment(words)
    }
}
