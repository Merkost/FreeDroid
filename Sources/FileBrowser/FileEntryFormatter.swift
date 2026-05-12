import Foundation
import FreeDroidDomain

public enum FileEntryFormatter {
    public static func sizeString(for entry: RemoteEntry) -> String? {
        guard entry.kind != .directory, let size = entry.sizeBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: size)
    }

    public static func modifiedString(for entry: RemoteEntry, relativeTo reference: Date = .now) -> String? {
        guard let modified = entry.modifiedAt else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(modified) {
            return modified.formatted(date: .omitted, time: .shortened)
        }
        if let yearDelta = calendar.dateComponents([.year], from: modified, to: reference).year, yearDelta == 0 {
            return modified.formatted(.dateTime.month(.abbreviated).day())
        }
        return modified.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
