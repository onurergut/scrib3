import Foundation

public enum EngineIdentifier: String, Sendable, CaseIterable {
    case apple
    case whisperKit
}

public struct EngineProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case downloading
        case transcribing
    }

    public let phase: Phase
    /// Zero through one, or `nil` when the engine cannot estimate progress.
    public let fraction: Double?

    public init(phase: Phase, fraction: Double?) {
        self.phase = phase
        self.fraction = fraction.map { min(1, max(0, $0)) }
    }

    public static func downloading(_ fraction: Double?) -> EngineProgress {
        EngineProgress(phase: .downloading, fraction: fraction)
    }

    public static func transcribing(_ fraction: Double?) -> EngineProgress {
        EngineProgress(phase: .transcribing, fraction: fraction)
    }
}

/// A speech-to-text backend. Engines only convert audio into timed words;
/// cue segmentation and subtitle formatting stay engine-independent.
public protocol TranscriptionEngine: Sendable {
    var identifier: EngineIdentifier { get }
    var displayName: String { get }

    func supportedLocales() async throws -> [Locale]
    func installedLocales() async throws -> [Locale]

    /// Downloads any model assets needed for `locale`. Safe to call again.
    func prepare(
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws

    /// Transcribes the audio track of a media file. Cancelling the calling
    /// task stops the engine.
    func transcribe(
        file: URL,
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws -> [TimedWord]
}

public enum TranscriptionError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedLocale(String)
    case engineUnavailable(EngineIdentifier)
    case notAMediaFile(String)
    case audioReadFailed(String)
    case assetDownloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let identifier):
            "This language is not supported by the selected engine (\(identifier))."
        case .engineUnavailable(let identifier):
            "The \(identifier.rawValue) engine is not available on this Mac."
        case .notAMediaFile(let name):
            "\(name) does not contain an audio track scrib3 can read."
        case .audioReadFailed(let message):
            "The audio could not be read: \(message)"
        case .assetDownloadFailed(let message):
            "The language model could not be downloaded: \(message)"
        }
    }
}
