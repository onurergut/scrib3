import AppKit
import Scrib3Core
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        HSplitView {
            QueueSidebar()
                .frame(minWidth: 330, idealWidth: 360, maxWidth: 440)

            DetailPane()
                .frame(minWidth: 540, maxWidth: .infinity)
        }
        .frame(minHeight: 560)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Task { await model.acceptDrop(providers) }
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .alert(
            "scrib3",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Sidebar

private struct QueueSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            header
            dropZone
            controls(selection: $model.selectedLocaleID)
            Divider()
            queueHeader
            queueList
            footer
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("scrib3")
                    .font(.title2.weight(.semibold))
                Text("On-device transcripts, saved as subtitles.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dropZone: some View {
        Button(action: addFiles) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .font(.title3)
                Text("Drop video or audio files")
                    .font(.callout.weight(.medium))
                Text("or choose files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func controls(selection: Binding<String>) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Language")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isLoadingLanguages {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Picker("Language", selection: selection) {
                ForEach(model.locales) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .labelsHidden()
            .disabled(model.locales.isEmpty)
            .onChange(of: selection.wrappedValue) { _, value in
                model.changeLanguage(to: value)
            }

            HStack {
                Text("Engine")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Picker(
                "Engine",
                selection: Binding(
                    get: { model.engine },
                    set: { model.changeEngine(to: $0) }
                )
            ) {
                Text("Apple Speech").tag(EngineIdentifier.apple)
                Text("WhisperKit").tag(EngineIdentifier.whisperKit)
            }
            .labelsHidden()
            .disabled(model.isBusy)

            Text(engineNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var engineNote: String {
        switch model.engine {
        case .apple:
            return "Apple downloads its speech model once, then works offline."
        case .whisperKit:
            return "Better Turkish punctuation. Downloads a 626 MB model once from Hugging Face."
        }
    }

    private var queueHeader: some View {
        HStack {
            Text("Queue")
                .font(.headline)
            Spacer()
            Text(entrySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var entrySummary: String {
        let total = model.entries.count
        if total == 0 { return "Empty" }
        let finished = model.finishedEntries.count
        return "\(finished)/\(total) ready"
    }

    private var queueList: some View {
        Group {
            if model.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Nothing queued yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.entries) { entry in
                            QueueRow(entry: entry)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let notice = model.noticeMessage {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button("Cancel") { model.cancelAll() }
                    .disabled(!model.isBusy)

                Button("Retry failed") { model.retryFailed() }
                    .disabled(!model.hasFailures)

                Spacer()

                Menu("Export all") {
                    ForEach(SubtitleFormat.allCases) { format in
                        Button(format.rawValue.uppercased()) {
                            model.exportAll(format: format)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.finishedEntries.isEmpty)

                Button {
                    model.clearFinished()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear finished items")
                .disabled(model.finishedEntries.isEmpty)
            }
            .controlSize(.small)

            Text("Files never leave your Mac. Model assets download once.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .audio]
        panel.prompt = "Add"

        if panel.runModal() == .OK {
            model.addFiles(panel.urls)
        }
    }
}

private struct QueueRow: View {
    @Environment(AppModel.self) private var model
    let entry: TranscriptionQueue.Entry

    private var isSelected: Bool { model.selectedID == entry.id }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                if entry.status == .finished {
                    model.select(entry.id)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(iconColor)
                        .frame(width: 18)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.url.lastPathComponent)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)

                        Text(statusLine)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                            .lineLimit(2)

                        if let fraction = model.progressFraction(for: entry) {
                            ProgressView(value: fraction)
                                .controlSize(.small)
                        } else if model.isRunning(entry) {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entry.status != .finished)

            Button {
                model.remove(entry.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Remove")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .contextMenu {
            if entry.status == .finished {
                Button("Show transcript") { model.select(entry.id) }
            }
            Button("Reveal in Finder") { model.revealSource(entry) }
            Divider()
            Button("Remove", role: .destructive) { model.remove(entry.id) }
        }
    }

    private var statusLine: String {
        "\(model.statusText(for: entry)) · \(model.localeName(for: entry))"
    }

    private var icon: String {
        switch entry.status {
        case .waiting: "clock"
        case .running: "waveform"
        case .finished: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var iconColor: Color {
        switch entry.status {
        case .finished: .green
        case .failed: .orange
        case .cancelled: .secondary
        case .waiting, .running: .accentColor
        }
    }

    private var statusColor: Color {
        if case .failed = entry.status { return .orange }
        return .secondary
    }
}

// MARK: - Detail

private struct DetailPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let entry = model.selectedEntry, entry.status == .finished {
            TranscriptPane(entry: entry)
        } else {
            EmptyDetailView()
        }
    }
}

private struct EmptyDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("Subtitle-ready transcripts")
                    .font(.title3.weight(.semibold))
                Text("Add a video or audio file, pick a language, and let scrib3 write the subtitle file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            HStack(spacing: 18) {
                Label("SRT · VTT · TXT", systemImage: "doc.text")
                Label("On-device", systemImage: "lock")
                Label("Editable cues", systemImage: "pencil")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let entry = model.entries.first(where: { entry in
                if case .failed = entry.status { return true }
                return false
            }) {
                VStack(spacing: 8) {
                    Text("Last failure: \(entry.url.lastPathComponent)")
                        .font(.caption)
                    Text(model.statusText(for: entry))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Retry failed") { model.retryFailed() }
                        .controlSize(.small)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct TranscriptPane: View {
    @Environment(AppModel.self) private var model
    let entry: TranscriptionQueue.Entry

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let playback = model.playback {
                PlayerSurface(player: playback.player)
                    .frame(height: 230)
                    .background(.black)
                Divider()
            }
            cueList
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(model.transcriptCues.count) cues · \(model.localeName(for: entry))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.revealSource(entry)
            } label: {
                Image(systemName: "folder")
            }
            .help("Reveal source in Finder")

            Menu("Export") {
                ForEach(SubtitleFormat.allCases) { format in
                    Button(format.rawValue.uppercased()) {
                        model.exportSelected(format: format)
                    }
                }
            }
            .disabled(!model.canExportSelection)
        }
        .padding(14)
    }

    private var cueList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Array(model.transcriptCues.enumerated()), id: \.offset) { index, cue in
                    CueRow(index: index, cue: cue)
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
    }
}

private struct CueRow: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let cue: SubtitleCue

    private var isCurrent: Bool {
        model.playback?.isPlaying(cue) == true
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                model.seek(to: cue)
            } label: {
                Text(cue.start.srtTimestamp)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Jump to this cue")

            TextField(
                "Subtitle text",
                text: Binding(
                    get: { cue.text },
                    set: { model.updateCue(at: index, text: $0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.body)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.accentColor.opacity(0.10) : Color.clear)
        )
    }
}
