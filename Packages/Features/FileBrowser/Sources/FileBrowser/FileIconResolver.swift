import FreeDroidDomain

public enum FileIconResolver {
    public static func symbol(for entry: RemoteEntry) -> String {
        if entry.kind == .directory { return "folder" }
        let lower = entry.name.lowercased()
        if let dot = lower.lastIndex(of: ".") {
            let ext = String(lower[lower.index(after: dot)...])
            return symbol(forExtension: ext)
        }
        return "doc"
    }

    private static func symbol(forExtension ext: String) -> String {
        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp", "gif", "bmp", "tiff": "photo"
        case "mp4", "mov", "m4v", "webm", "mkv", "avi": "play.rectangle"
        case "mp3", "m4a", "wav", "flac", "ogg": "music.note"
        case "pdf", "txt", "rtf", "doc", "docx", "md": "doc.richtext"
        case "zip", "tar", "gz", "7z", "rar": "archivebox"
        case "apk": "shippingbox"
        default: "doc"
        }
    }
}
