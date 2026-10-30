import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var servicesProvider: ServicesProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = ServicesProvider(model: model)
        servicesProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()

        let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if !arguments.isEmpty {
            model.addFiles(arguments.map { URL(fileURLWithPath: $0) })
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        model.addFiles(filenames.map { URL(fileURLWithPath: $0) })
        NSApp.activate()
        sender.reply(toOpenOrPrint: .success)
    }
}

/// Finder calls `transcribeWithScrib3:`, matching the `NSMessage` in Info.plist.
@MainActor
final class ServicesProvider: NSObject {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    @objc(transcribeWithScrib3:userData:error:)
    func transcribeWithScrib3(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let urls = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL]) ?? []

        guard !urls.isEmpty else {
            error.pointee = "Select one or more video or audio files." as NSString
            return
        }

        NSApp.activate()
        model.addFiles(urls)
    }
}
