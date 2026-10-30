import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Engines") {
                LabeledContent("Apple Speech") {
                    Text("Uses SpeechTranscriber where available and falls back to DictationTranscriber. macOS downloads the model once; after that it is offline.")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("WhisperKit") {
                    Text("Optional Core ML Whisper large-v3 model. Better Turkish punctuation. Downloaded once from Hugging Face (626 MB).")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Storage") {
                Text("WhisperKit models are stored in Application Support. Apple speech assets are managed by macOS and shared between apps.")
                    .foregroundStyle(.secondary)
                Button("Show model folder in Finder") {
                    let base = FileManager.default.urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    ).first ?? FileManager.default.temporaryDirectory
                    let folder = base
                        .appendingPathComponent("scrib3", isDirectory: true)
                        .appendingPathComponent("Models", isDirectory: true)
                    try? FileManager.default.createDirectory(
                        at: folder,
                        withIntermediateDirectories: true
                    )
                    NSWorkspace.shared.open(folder)
                }
            }

            Section("Privacy") {
                Text("Audio and video files are read on this Mac. Nothing is uploaded. Network access is used only for one-time model downloads: macOS speech assets, or the WhisperKit model when that engine is selected.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 430)
    }
}
