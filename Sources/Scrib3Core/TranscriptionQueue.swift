import Foundation

/// Sequential, observable work queue. The queue owns no UI and no engine;
/// callers supply the transcription operation.
public actor TranscriptionQueue {
    public typealias Executor = @Sendable (
        URL,
        Locale,
        @escaping @Sendable (EngineProgress) -> Void
    ) async throws -> [SubtitleCue]

    public struct Entry: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let url: URL
        public var locale: Locale
        public var status: Status
        public var progress: EngineProgress?
        public var cues: [SubtitleCue]

        public init(
            id: UUID = UUID(),
            url: URL,
            locale: Locale,
            status: Status = .waiting,
            progress: EngineProgress? = nil,
            cues: [SubtitleCue] = []
        ) {
            self.id = id
            self.url = url
            self.locale = locale
            self.status = status
            self.progress = progress
            self.cues = cues
        }
    }

    public enum Status: Sendable, Equatable {
        case waiting
        case running
        case finished
        case failed(String)
        case cancelled
    }

    public private(set) var entries: [Entry] = []
    public nonisolated let updates: AsyncStream<[Entry]>

    private let executor: Executor
    private let updatesContinuation: AsyncStream<[Entry]>.Continuation
    private var isRunning = false
    private var currentTask: Task<Void, Never>?

    public init(executor: @escaping Executor) {
        self.executor = executor
        let pair = AsyncStream.makeStream(
            of: [Entry].self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.updates = pair.stream
        self.updatesContinuation = pair.continuation
    }

    // MARK: - Commands

    public func add(_ urls: [URL], locale: Locale) {
        var seen = Set(entries.map { $0.url.standardizedFileURL })
        var changed = false

        for url in urls {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized).inserted else { continue }
            entries.append(Entry(url: url, locale: locale))
            changed = true
        }

        guard changed else { return }
        publish()
        startIfNeeded()
    }

    public func start() {
        startIfNeeded()
    }

    public func cancel() {
        currentTask?.cancel()
        for index in entries.indices where entries[index].status == .waiting {
            entries[index].status = .cancelled
        }
        publish()
    }

    public func retryFailed() {
        var changed = false
        for index in entries.indices {
            guard case .failed = entries[index].status else { continue }
            entries[index].status = .waiting
            entries[index].progress = nil
            entries[index].cues = []
            changed = true
        }
        guard changed else { return }
        publish()
        startIfNeeded()
    }

    public func setLocale(_ locale: Locale, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].status == .waiting
        else { return }
        entries[index].locale = locale
        publish()
    }

    public func updateCues(_ cues: [SubtitleCue], for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].cues = cues
        publish()
    }

    public func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        publish()
    }

    public func clearFinished() {
        entries.removeAll { entry in
            entry.status == .finished || entry.status == .cancelled
        }
        publish()
    }

    // MARK: - Running

    private func startIfNeeded() {
        guard !isRunning,
              entries.contains(where: { $0.status == .waiting })
        else { return }

        isRunning = true
        currentTask = Task { await self.runLoop() }
    }

    private func runLoop() async {
        defer {
            isRunning = false
            currentTask = nil
            publish()
            startIfNeeded()
        }

        while !Task.isCancelled {
            guard let entry = entries.first(where: { $0.status == .waiting }) else {
                return
            }
            let id = entry.id
            setStatus(.running, progress: nil, for: id)
            publish()

            do {
                let cues = try await executor(entry.url, entry.locale) { [weak self] progress in
                    Task { await self?.setProgress(progress, for: id) }
                }
                if Task.isCancelled {
                    setStatus(.cancelled, progress: nil, for: id)
                } else {
                    setCues(cues, for: id)
                    setStatus(.finished, progress: .transcribing(1), for: id)
                }
            } catch is CancellationError {
                setStatus(.cancelled, progress: nil, for: id)
            } catch {
                setStatus(.failed(error.localizedDescription), progress: nil, for: id)
            }
            publish()
        }
    }

    // MARK: - Mutation helpers

    private func setProgress(_ progress: EngineProgress, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].status == .running
        else { return }

        if let current = entries[index].progress,
           current.phase == progress.phase,
           let previous = current.fraction,
           let next = progress.fraction,
           next < previous
        {
            return
        }

        entries[index].progress = progress
        publish()
    }

    private func setStatus(_ status: Status, progress: EngineProgress?, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = status
        entries[index].progress = progress
    }

    private func setCues(_ cues: [SubtitleCue], for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].cues = cues
    }

    private func publish() {
        updatesContinuation.yield(entries)
    }
}
