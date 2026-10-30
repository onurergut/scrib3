import Foundation
import Testing
@testable import Scrib3Core

@Suite("TranscriptionQueue")
struct TranscriptionQueueTests {
    private let english = Locale(identifier: "en_US")
    private let fileA = URL(fileURLWithPath: "/tmp/a.wav")
    private let fileB = URL(fileURLWithPath: "/tmp/b.wav")

    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @Sendable () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for queue state")
    }

    @Test func runsAddedFilesSequentially() async throws {
        let recorder = CallRecorder()
        let queue = TranscriptionQueue { url, _, progress in
            await recorder.record(url)
            progress(.transcribing(0.5))
            progress(.transcribing(1))
            return [SubtitleCue(start: 0, end: 1, text: url.lastPathComponent)]
        }

        await queue.add([fileA, fileB], locale: english)
        try await waitUntil {
            let entries = await queue.entries
            return entries.count == 2 && entries.allSatisfy { $0.status == .finished }
        }

        let calls = await recorder.calls
        #expect(calls == [fileA, fileB])
        let entries = await queue.entries
        #expect(entries[0].cues.map(\.text) == ["a.wav"])
        #expect(entries[1].cues.map(\.text) == ["b.wav"])
    }

    @Test func ignoresDuplicateURLs() async throws {
        let queue = TranscriptionQueue { _, _, _ in
            [SubtitleCue(start: 0, end: 1, text: "x")]
        }
        await queue.add([fileA, fileA], locale: english)
        try await waitUntil { await queue.entries.count == 1 }
        let count = await queue.entries.count
        #expect(count == 1)
    }

    @Test func marksFailuresAndRetriesOnlyThose() async throws {
        let gate = FailureGate(failingName: "b.wav")
        let recorder = CallRecorder()
        let queue = TranscriptionQueue { url, _, _ in
            await recorder.record(url)
            if await gate.shouldFail(url) {
                throw TranscriptionError.audioReadFailed("boom")
            }
            return [SubtitleCue(start: 0, end: 1, text: url.lastPathComponent)]
        }

        await queue.add([fileA, fileB], locale: english)
        try await waitUntil {
            let entries = await queue.entries
            let hasFinished = entries.contains { $0.status == .finished }
            let hasFailed = entries.contains { entry in
                if case .failed = entry.status { return true }
                return false
            }
            return hasFinished && hasFailed
        }

        await gate.stopFailing()
        await queue.retryFailed()
        try await waitUntil {
            let entries = await queue.entries
            return entries.count == 2 && entries.allSatisfy { $0.status == .finished }
        }

        let calls = await recorder.calls
        #expect(calls == [fileA, fileB, fileB])
    }

    @Test func storesLatestProgress() async throws {
        let gate = PauseGate()
        let queue = TranscriptionQueue { _, _, progress in
            progress(.transcribing(0.42))
            await gate.waitForRelease()
            return []
        }

        await queue.add([fileA], locale: english)
        try await waitUntil {
            await queue.entries.first?.progress == .transcribing(0.42)
        }
        let progress = await queue.entries.first?.progress
        #expect(progress == .transcribing(0.42))

        await gate.release()
        try await waitUntil {
            await queue.entries.first?.status == .finished
        }
    }

    @Test func cancelStopsRunningAndPendingWork() async throws {
        let queue = TranscriptionQueue { _, _, _ in
            try await Task.sleep(for: .seconds(10))
            return []
        }

        await queue.add([fileA, fileB], locale: english)
        try await waitUntil {
            await queue.entries.first?.status == .running
        }

        await queue.cancel()
        try await waitUntil {
            let entries = await queue.entries
            return entries.allSatisfy { $0.status == .cancelled }
        }

        let entries = await queue.entries
        #expect(entries.map(\.status) == [.cancelled, .cancelled])
    }

    @Test func removeDropsAnEntry() async throws {
        let queue = TranscriptionQueue { _, _, _ in
            [SubtitleCue(start: 0, end: 1, text: "x")]
        }
        await queue.add([fileA], locale: english)
        let id = try #require(await queue.entries.first?.id)
        await queue.remove(id)
        let remaining = await queue.entries
        #expect(remaining.isEmpty)
    }

    @Test func changeLocaleAppliesToWaitingItems() async throws {
        let gate = PauseGate()
        let recorder = CallRecorder()
        let queue = TranscriptionQueue { url, locale, _ in
            await recorder.recordLocale(locale, for: url)
            if url == self.fileA {
                await gate.waitForRelease()
            }
            return []
        }

        await queue.add([fileA, fileB], locale: english)
        try await waitUntil { await queue.entries.first?.status == .running }
        let entries = await queue.entries
        let secondID = try #require(entries.last?.id)
        await queue.setLocale(Locale(identifier: "tr_TR"), for: secondID)
        await gate.release()

        try await waitUntil {
            await queue.entries.allSatisfy { $0.status == .finished }
        }
        let locales = await recorder.locales
        #expect(locales[fileB]?.identifier == "tr_TR")
    }
}

private actor CallRecorder {
    private(set) var calls: [URL] = []
    private(set) var locales: [URL: Locale] = [:]

    func record(_ url: URL) {
        calls.append(url)
    }

    func recordLocale(_ locale: Locale, for url: URL) {
        locales[url] = locale
    }
}

private actor FailureGate {
    private let failingName: String
    private var failing = true

    init(failingName: String) {
        self.failingName = failingName
    }

    func shouldFail(_ url: URL) -> Bool {
        failing && url.lastPathComponent == failingName
    }

    func stopFailing() {
        failing = false
    }
}

private actor PauseGate {
    private var isReleased = false

    func waitForRelease() async {
        while !isReleased {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func release() {
        isReleased = true
    }
}
