import AppKit
import Scrib3Core
import SwiftUI

@main
struct Scrib3App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var model: AppModel { delegate.model }

    var body: some Scene {
        Window("scrib3", id: "main") {
            ContentView()
                .environment(model)
                .onOpenURL { url in
                    model.addFiles([url])
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Add Files…") { addFiles() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Cancel Queue") { model.cancelAll() }
                    .keyboardShortcut(".", modifiers: .command)
                Button("Retry Failed") { model.retryFailed() }
            }

            CommandMenu("Export") {
                ForEach(SubtitleFormat.allCases) { format in
                    Button("Export Selected as \(format.rawValue.uppercased())") {
                        model.exportSelected(format: format)
                    }
                }
                Divider()
                ForEach(SubtitleFormat.allCases) { format in
                    Button("Export All as \(format.rawValue.uppercased())") {
                        model.exportAll(format: format)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
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
