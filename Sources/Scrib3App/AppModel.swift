import AppKit
import AVFoundation
import Foundation
import Observation
import Scrib3Core
import UniformTypeIdentifiers

struct LocaleOption: Identifiable, Hashable {
    let locale: Locale

    var id: String { locale.bcp47Key }

    var displayName: String {
        Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }
}

@MainActor
@Observable
final class AppModel {
    let appleEngine: AppleSpeechEngine
    let whisperEngine: WhisperKitEngine
    let queue: TranscriptionQueue

    private let router: EngineRouter
    private var updatesTask: Task<Void, Never>?

    private(set) var entries: [TranscriptionQueue.Entry] = []
    private(set) var transcriptCues: [SubtitleCue] = []
    private(set) var transcriptSourceID: UUID?
    private(set) var playback: PlaybackModel?

    var selectedID: UUID?
    var engine: EngineIdentifier = .apple
    var locales: [LocaleOption] = []
    var selectedLocaleID = ""
    var isLoadingLanguages = true
    var errorMessage: String?
    var noticeMessage: String?

    init() {
        let apple = AppleSpeechEngine()
        appleEngine = apple
        whisperEngine = WhisperKitEngine()

        let router = EngineRouter(engine: apple)
        self.router = router
        queue = TranscriptionQueue { url, locale, progress in
            try await router.transcribe(file: url, locale: locale, progress: progress)
        }

        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in self.queue.updates {
                self.apply(snapshot)
            }
        }

        Task { [weak self] in
            await self?.reloadLanguages(selectDefault: true)
        }
    }

    // MARK: - Derived state

    var selectedEntry: TranscriptionQueue.Entry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }

    var selectedLocale: Locale {
        if let option = locales.first(where: { $0.id == selectedLocaleID }) {
            return option.locale
        }
        if !selectedLocaleID.isEmpty {
            return Locale(identifier: selectedLocaleID)
        }
        return Locale.current
    }

    var isBusy: Bool {
        entries.contains { $0.status == .running }
    }

    var hasFailures: Bool {
        entries.contains { entry in
            if case .failed = entry.status { return true }
            return false
        }
    }

    var finishedEntries: [TranscriptionQueue.Entry] {
        entries.filter { $0.status == .finished }
    }

    var canExportSelection: Bool {
        selectedEntry?.status == .finished
    }

    var currentEngine: any TranscriptionEngine {
        engine == .apple ? appleEngine : whisperEngine
    }

    // MARK: - Languages and engine

    func changeEngine(to identifier: EngineIdentifier) {
        guard identifier != engine, !isBusy else { return }
        engine = identifier
        let chosen = currentEngine
        Task {
            await router.setEngine(chosen)
            await reloadLanguages(selectDefault: true)
        }
    }

    func changeLanguage(to identifier: String) {
        guard identifier != selectedLocaleID else { return }
        selectedLocaleID = identifier
        let locale = selectedLocale
        Task {
            for entry in await queue.entries where entry.status == .waiting {
                await queue.setLocale(locale, for: entry.id)
            }
        }
    }

    func reloadLanguages(selectDefault: Bool) async {
        isLoadingLanguages = true
        defer { isLoadingLanguages = false }

        do {
            let supported = try await currentEngine.supportedLocales()
            let options = supported
                .map(LocaleOption.init)
                .sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
            locales = options

            if selectDefault
                || !options.contains(where: { $0.id == selectedLocaleID })
            {
                selectedLocaleID = defaultLocale(from: options)?.id
                    ?? options.first?.id
                    ?? ""
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func defaultLocale(from options: [LocaleOption]) -> LocaleOption? {
        let system = SystemLanguage.preferredLocale
        if let exact = options.first(where: { $0.locale.bcp47Key == system.bcp47Key }) {
            return exact
        }
        let languageCode = system.language.languageCode?.identifier.lowercased()
        if let sameLanguage = options.first(where: {
            $0.locale.language.languageCode?.identifier.lowercased() == languageCode
        }) {
            return sameLanguage
        }
        if let english = options.first(where: {
            $0.locale.language.languageCode?.identifier == "en"
        }) {
            return english
        }
        return options.first
    }

    // MARK: - Files

    func addFiles(_ urls: [URL]) {
        let supported = urls.filter(Self.isSupportedMedia)
        guard !supported.isEmpty else {
            errorMessage = "Choose a video or audio file."
            return
        }

        let chosen = currentEngine
        Task {
            if locales.isEmpty {
                await reloadLanguages(selectDefault: true)
            }
            await router.setEngine(chosen)
            await queue.add(supported, locale: selectedLocale)
        }
    }

    func acceptDrop(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            guard let item = try? await provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier
            ) else { continue }

            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil)
            {
                urls.append(url)
            } else if let url = item as? URL {
                urls.append(url)
            }
        }
        addFiles(urls)
    }

    func cancelAll() {
        Task { await queue.cancel() }
    }

    func retryFailed() {
        Task { await queue.retryFailed() }
    }

    func clearFinished() {
        Task {
            await queue.clearFinished()
            let remaining = await queue.entries
            if let selectedID, !remaining.contains(where: { $0.id == selectedID }) {
                clearTranscript()
                self.selectedID = nil
            }
        }
    }

    func remove(_ id: UUID) {
        Task {
            await queue.remove(id)
            if selectedID == id {
                clearTranscript()
                selectedID = nil
            }
        }
    }

    func revealSource(_ entry: TranscriptionQueue.Entry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    // MARK: - Selection and editing

    func select(_ id: UUID?) {
        selectedID = id
        guard let id,
              let entry = entries.first(where: { $0.id == id }),
              entry.status == .finished
        else {
            clearTranscript()
            return
        }
        loadTranscript(entry)
    }

    private func loadTranscript(_ entry: TranscriptionQueue.Entry) {
        guard transcriptSourceID != entry.id else { return }
        playback?.stop()
        transcriptSourceID = entry.id
        transcriptCues = entry.cues.map { cue in
            SubtitleCue(
                start: cue.start,
                end: cue.end,
                text: cue.text
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
            )
        }
        playback = PlaybackModel(url: entry.url)
    }

    private func clearTranscript() {
        playback?.stop()
        playback = nil
        transcriptSourceID = nil
        transcriptCues = []
    }

    private func apply(_ snapshot: [TranscriptionQueue.Entry]) {
        entries = snapshot

        guard let selectedID else { return }
        guard let entry = snapshot.first(where: { $0.id == selectedID }) else {
            clearTranscript()
            self.selectedID = nil
            return
        }

        if entry.status == .finished, transcriptSourceID != entry.id {
            loadTranscript(entry)
        }
    }

    func updateCue(at index: Int, text: String) {
        guard let sourceID = transcriptSourceID,
              transcriptCues.indices.contains(index)
        else { return }

        transcriptCues[index].text = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        let snapshot = transcriptCues
        Task { await queue.updateCues(snapshot, for: sourceID) }
    }

    func seek(to cue: SubtitleCue) {
        playback?.seek(to: cue.start.seconds)
    }

    // MARK: - Export

    func exportSelected(format: SubtitleFormat) {
        guard let entry = selectedEntry, entry.status == .finished else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = OutputNaming.outputURL(
            source: entry.url,
            format: format
        ).lastPathComponent
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try SubtitleExporter.write(
                cues: wrapped(transcriptCues),
                format: format,
                to: url
            )
            noticeMessage = "Exported \(url.lastPathComponent)."
        } catch {
            errorMessage = "Could not export the subtitle file: \(error.localizedDescription)"
        }
    }

    func exportAll(format: SubtitleFormat) {
        let finished = finishedEntries
        guard !finished.isEmpty else {
            errorMessage = "There is nothing to export yet."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let directory = panel.url else { return }

        var failures = 0
        for entry in finished {
            let url = OutputNaming.outputURL(
                source: entry.url,
                format: format,
                directory: directory
            )
            do {
                try SubtitleExporter.write(
                    cues: wrapped(entry.cues),
                    format: format,
                    to: url
                )
            } catch {
                failures += 1
            }
        }

        if failures == 0 {
            noticeMessage = "Exported \(finished.count) subtitle file(s)."
        } else {
            errorMessage = "\(failures) of \(finished.count) exports failed."
        }
    }

    private func wrapped(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        cues.map { cue in
            SubtitleCue(
                start: cue.start,
                end: cue.end,
                text: LineWrapper.wrap(cue.text)
            )
        }
    }

    // MARK: - Status text

    func statusText(for entry: TranscriptionQueue.Entry) -> String {
        switch entry.status {
        case .waiting:
            return "Waiting"
        case .running:
            guard let progress = entry.progress else { return "Starting…" }
            switch progress.phase {
            case .downloading:
                if let fraction = progress.fraction {
                    return "Preparing model \(Int(fraction * 100))%"
                }
                return "Preparing model…"
            case .transcribing:
                if let fraction = progress.fraction {
                    return "Transcribing \(Int(fraction * 100))%"
                }
                return "Transcribing…"
            }
        case .finished:
            return "Ready"
        case .failed(let message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }

    func progressFraction(for entry: TranscriptionQueue.Entry) -> Double? {
        guard entry.status == .running else { return nil }
        return entry.progress?.fraction
    }

    func isRunning(_ entry: TranscriptionQueue.Entry) -> Bool {
        entry.status == .running
    }

    func localeName(for entry: TranscriptionQueue.Entry) -> String {
        Locale.current.localizedString(forIdentifier: entry.locale.identifier)
            ?? entry.locale.identifier
    }

    private static func isSupportedMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .movie) || type.conforms(to: .audio)
    }
}

/// `Locale.current` follows the app's localization, which can fall back to the
/// bundle development region. The transcription language should follow the
/// system-wide preference instead.
enum SystemLanguage {
    static var preferredLocale: Locale {
        let domain = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")
        if let languages = domain?["AppleLanguages"] as? [String],
           let first = languages.first
        {
            return Locale(identifier: first)
        }
        return Locale.current
    }
}
