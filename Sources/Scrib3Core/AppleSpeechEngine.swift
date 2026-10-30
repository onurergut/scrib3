import AVFoundation
import Foundation
import Speech

/// On-device transcription through Apple's Speech framework.
///
/// `SpeechTranscriber` is used wherever Apple supports it. For locales that
/// only the system-dictation models cover (Turkish, for example) the engine
/// falls back to `DictationTranscriber` inside the same `SpeechAnalyzer`.
public struct AppleSpeechEngine: TranscriptionEngine {
    public let identifier: EngineIdentifier = .apple
    public let displayName = "Apple Speech"

    public init() {}

    public func supportedLocales() async throws -> [Locale] {
        let speech = await SpeechTranscriber.supportedLocales
        let dictation = await DictationTranscriber.supportedLocales
        let merged = AppleLocaleSupport.merged(speech: speech, dictation: dictation)
        guard !merged.isEmpty else {
            throw TranscriptionError.engineUnavailable(.apple)
        }
        return merged
    }

    public func installedLocales() async throws -> [Locale] {
        let speech = await SpeechTranscriber.installedLocales
        let dictation = await DictationTranscriber.installedLocales
        return AppleLocaleSupport.merged(speech: speech, dictation: dictation)
    }

    public func prepare(
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws {
        let choice = try await makeModule(for: locale)
        let status = await AssetInventory.status(forModules: [choice.module])

        switch status {
        case .unsupported:
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        case .installed:
            progress(.downloading(1))
            return
        case .supported, .downloading:
            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: [choice.module]
            ) else {
                progress(.downloading(1))
                return
            }
            try await install(request, progress: progress)
        @unknown default:
            throw TranscriptionError.assetDownloadFailed("Unknown asset status.")
        }
    }

    public func transcribe(
        file: URL,
        locale: Locale,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws -> [TimedWord] {
        try await prepare(locale: locale, progress: progress)
        let choice = try await makeModule(for: locale)

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: file)
        } catch {
            throw TranscriptionError.notAMediaFile(file.lastPathComponent)
        }
        guard audioFile.length > 0 else {
            throw TranscriptionError.audioReadFailed("The audio track is empty.")
        }

        let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [choice.module]
        ) ?? audioFile.processingFormat

        let analyzer = SpeechAnalyzer(modules: [choice.module])
        try await analyzer.prepareToAnalyze(in: targetFormat)

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let feeder = AudioFeeder(url: file, targetFormat: targetFormat)
        let feeding = Task {
            try await feeder.feed(into: continuation, progress: progress)
        }
        let collecting = Task {
            try await Self.collectWords(from: choice)
        }

        progress(.transcribing(0))

        do {
            try await withTaskCancellationHandler {
                try await analyzer.start(inputSequence: stream)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } onCancel: {
                feeding.cancel()
                collecting.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }

            let words = try await collecting.value
            try await feeding.value
            try Task.checkCancellation()
            progress(.transcribing(1))
            return words
        } catch {
            feeding.cancel()
            collecting.cancel()
            throw error
        }
    }

    // MARK: - Assets

    private func install(
        _ request: AssetInstallationRequest,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) async throws {
        progress(.downloading(request.progress.fractionCompleted))

        let monitor = Task {
            while !Task.isCancelled {
                progress(.downloading(request.progress.fractionCompleted))
                if request.progress.isFinished { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { monitor.cancel() }

        do {
            try await request.downloadAndInstall()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriptionError.assetDownloadFailed(error.localizedDescription)
        }
        progress(.downloading(1))
    }

    // MARK: - Modules

    private enum ModuleChoice: Sendable {
        case speechTranscriber(SpeechTranscriber)
        case dictationTranscriber(DictationTranscriber)

        var module: any SpeechModule {
            switch self {
            case .speechTranscriber(let module): module
            case .dictationTranscriber(let module): module
            }
        }
    }

    private func makeModule(for locale: Locale) async throws -> ModuleChoice {
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speechTranscriber(
                SpeechTranscriber(
                    locale: equivalent,
                    preset: .timeIndexedTranscriptionWithAlternatives
                )
            )
        }

        if let equivalent = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictationTranscriber(
                DictationTranscriber(
                    locale: equivalent,
                    contentHints: [],
                    transcriptionOptions: [.punctuation],
                    reportingOptions: [.frequentFinalization],
                    attributeOptions: [.audioTimeRange, .transcriptionConfidence]
                )
            )
        }

        throw TranscriptionError.unsupportedLocale(locale.identifier)
    }

    private static func collectWords(from choice: ModuleChoice) async throws -> [TimedWord] {
        var words: [TimedWord] = []

        switch choice {
        case .speechTranscriber(let module):
            for try await result in module.results {
                guard result.isFinal else { continue }
                words.append(contentsOf: SpeechTextReader.words(from: result.text))
            }
        case .dictationTranscriber(let module):
            for try await result in module.results {
                guard result.isFinal else { continue }
                words.append(contentsOf: SpeechTextReader.words(from: result.text))
            }
        }

        return words
    }
}

/// Reads the audio track in one-second chunks, converts it to the analyzer's
/// preferred format, and reports progress from the bytes consumed.
private actor AudioFeeder {
    private let url: URL
    private let targetFormat: AVAudioFormat

    init(url: URL, targetFormat: AVAudioFormat) {
        self.url = url
        self.targetFormat = targetFormat
    }

    func feed(
        into continuation: AsyncStream<AnalyzerInput>.Continuation,
        progress: @escaping @Sendable (EngineProgress) -> Void
    ) throws {
        defer { continuation.finish() }

        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else {
            throw TranscriptionError.audioReadFailed("The audio track is empty.")
        }

        let sourceFormat = file.processingFormat
        let needsConversion = Self.needsConversion(from: sourceFormat, to: targetFormat)
        let converter = needsConversion
            ? AVAudioConverter(from: sourceFormat, to: targetFormat)
            : nil
        if needsConversion, converter == nil {
            throw TranscriptionError.audioReadFailed("Unsupported audio format.")
        }

        let chunkFrames = AVAudioFrameCount(max(1, sourceFormat.sampleRate))
        let totalFrames = Double(file.length)
        var fedFrames: Double = 0

        while !Task.isCancelled {
            guard let input = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: chunkFrames
            ) else {
                throw TranscriptionError.audioReadFailed("Out of memory while reading audio.")
            }

            do {
                try file.read(into: input)
            } catch {
                // AVAudioFile reports end of file as an error.
                break
            }
            if input.frameLength == 0 { break }

            fedFrames += Double(input.frameLength)

            if let converter {
                let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
                let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
                guard let output = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: capacity
                ) else {
                    throw TranscriptionError.audioReadFailed("Out of memory while converting audio.")
                }

                var suppliedInput = false
                var conversionError: NSError?
                let status = converter.convert(
                    to: output,
                    error: &conversionError
                ) { _, outStatus in
                    if suppliedInput {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    suppliedInput = true
                    outStatus.pointee = .haveData
                    return input
                }

                if status == .error {
                    throw TranscriptionError.audioReadFailed(
                        conversionError?.localizedDescription ?? "Audio conversion failed."
                    )
                }
                if output.frameLength > 0 {
                    continuation.yield(AnalyzerInput(buffer: output))
                }
            } else {
                continuation.yield(AnalyzerInput(buffer: input))
            }

            progress(.transcribing(min(1, fedFrames / totalFrames)))
        }

        try Task.checkCancellation()
    }

    private static func needsConversion(from source: AVAudioFormat, to target: AVAudioFormat) -> Bool {
        source.sampleRate != target.sampleRate
            || source.channelCount != target.channelCount
            || source.commonFormat != target.commonFormat
            || source.isInterleaved != target.isInterleaved
    }
}
