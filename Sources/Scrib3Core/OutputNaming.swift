import Foundation

public enum OutputNaming {
    public static func baseName(for source: URL) -> String {
        source.deletingPathExtension().lastPathComponent
    }

    public static func outputURL(
        source: URL,
        format: SubtitleFormat,
        directory: URL? = nil
    ) -> URL {
        let name = baseName(for: source)
        let folder = directory ?? source.deletingLastPathComponent()
        return folder
            .appendingPathComponent(name)
            .appendingPathExtension(format.fileExtension)
    }
}
