import Foundation
import FreeDroidDomain

public enum FileSortOption: String, CaseIterable, Sendable {
    case name, size, modified, kind

    public func apply(_ entries: [RemoteEntry], ascending: Bool) -> [RemoteEntry] {
        let dirs = entries.filter { $0.kind == .directory }
        let files = entries.filter { $0.kind != .directory }
        let sortedDirs = dirs.sorted(by: comparator(ascending: ascending))
        let sortedFiles = files.sorted(by: comparator(ascending: ascending))
        return sortedDirs + sortedFiles
    }

    private func comparator(ascending: Bool) -> (RemoteEntry, RemoteEntry) -> Bool {
        switch self {
        case .name:
            { lhs, rhs in
                let result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
        case .size:
            { lhs, rhs in
                let leftSize = lhs.sizeBytes ?? 0
                let rightSize = rhs.sizeBytes ?? 0
                return ascending ? leftSize < rightSize : leftSize > rightSize
            }
        case .modified:
            { lhs, rhs in
                let leftDate = lhs.modifiedAt ?? .distantPast
                let rightDate = rhs.modifiedAt ?? .distantPast
                return ascending ? leftDate < rightDate : leftDate > rightDate
            }
        case .kind:
            { lhs, rhs in
                let leftExt = lhs.name.split(separator: ".").last.map(String.init) ?? ""
                let rightExt = rhs.name.split(separator: ".").last.map(String.init) ?? ""
                let cmp = leftExt.localizedCaseInsensitiveCompare(rightExt)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        }
    }
}
