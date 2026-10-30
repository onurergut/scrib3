import Foundation
import WhisperKit

/// Core ML Whisper backend. Its multilingual model gives Turkish
/// capitalization and punctuation that the system dictation model omits.
/// The model is downloaded once from Hugging Face and cached locally.
public actor WhisperKitEngine: TranscriptionEngine {
    public nonisolated let identifier: EngineIdentifier = .whisperKit
    public nonisolated let displayName = "WhisperKit large-v3"

    private let downloadBase: URL
    private let modelVariant: String
    private var pipeline: WhisperKit?

    public init(
        downloadBase: URL? = nil,
        modelVariant: String = "large-v3-v20240930_626MB"
    ) {
        self.downloadBase = downloadBase ?? Self.defaultDownloadBase()
        self.modelVariant = modelVariant
    }

    public func supportedLocales() async throws -> [Locale] {
        WhisperLanguage.locales
    }

    public func installedLocales() async throws -> [Locale] {
        existingModelFolder() == nil ? [] : WhisperLanguage.locales
    }

    public func prepare(
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws {
        guard WhisperLanguage.code(for: locale) != nil else {
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        }
        if pipeline != nil {
            progress(.downloading(1))
            return
        }

        let folder: URL
        if let existing = existingModelFolder() {
            folder = existing
        } else {
            progress(.downloading(nil))
            do {
                folder = try await WhisperKit.download(
                    variant: modelVariant,
                    downloadBase: downloadBase,
                    progressCallback: { download in
                        progress(.downloading(download.fractionCompleted))
                    }
                )
            } catch {
                throw TranscriptionError.assetDownloadFailed(error.localizedDescription)
            }
            progress(.downloading(1))
        }

        progress(.downloading(nil))
        let config = WhisperKitConfig(
            model: modelVariant,
            downloadBase: downloadBase,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )

        do {
            pipeline = try await WhisperKit(config)
        } catch {
            throw TranscriptionError.preparationFailed(error.localizedDescription)
        }
        progress(.downloading(1))
    }

    public func transcribe(
        file: URL,
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws -> [TimedWord] {
        guard let language = WhisperLanguage.code(for: locale) else {
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw TranscriptionError.notAMediaFile(file.lastPathComponent)
        }

        try await prepare(locale: locale, progress: progress)
        guard let pipeline else {
            throw TranscriptionError.preparationFailed("The model is not loaded.")
        }

        let options = DecodingOptions(
            language: language,
            skipSpecialTokens: true,
            wordTimestamps: true
        )

        progress(.transcribing(nil))
        let results: [TranscriptionResult]
        do {
            results = try await pipeline.transcribe(
                audioPath: file.path,
                decodeOptions: options
            )
        } catch {
            throw TranscriptionError.audioReadFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        let words = WhisperWordMapper.words(from: results.flatMap(\.allWords))
        progress(.transcribing(1))
        return words
    }

    // MARK: - Model folder

    private var repositoryFolder: URL {
        downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
    }

    private func existingModelFolder() -> URL? {
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: repositoryFolder,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        for candidate in candidates where candidate.lastPathComponent.contains(modelVariant) {
            let encoder = candidate.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true)
            let encoderPackage = candidate.appendingPathComponent("AudioEncoder.mlpackage", isDirectory: true)
            if FileManager.default.fileExists(atPath: encoder.path)
                || FileManager.default.fileExists(atPath: encoderPackage.path)
            {
                return candidate
            }
        }
        return nil
    }

    private static func defaultDownloadBase() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("scrib3", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}

enum WhisperLanguage {
    static func code(for locale: Locale) -> String? {
        guard let code = locale.language.languageCode?.identifier.lowercased(),
              Constants.languageCodes.contains(code)
        else { return nil }
        return code
    }

    static var locales: [Locale] {
        var seen = Set<String>()
        return Constants.languages.values
            .sorted()
            .compactMap { code in
                guard seen.insert(code).inserted else { return nil }
                return Locale(identifier: code)
            }
    }
}

enum WhisperWordMapper {
    static func words(from timings: [WordTiming]) -> [TimedWord] {
        timings.compactMap { timing in
            let text = timing.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let rawStart = Double(timing.start)
            let rawEnd = Double(timing.end)
            guard rawStart.isFinite, rawEnd.isFinite else { return nil }

            let start = max(0, rawStart)
            let end = max(start, rawEnd)
            return TimedWord(
                text: text,
                start: start,
                end: end,
                confidence: Double(timing.probability)
            )
        }
    }
}
