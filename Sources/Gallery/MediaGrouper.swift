import Foundation
import FreeDroidDomain

public struct MediaGrouper: Sendable {
    private let formatter: GalleryDateFormatter

    public init(formatter: GalleryDateFormatter = GalleryDateFormatter()) {
        self.formatter = formatter
    }

    public func group(_ items: [MediaItem]) -> [MediaSection] {
        let withDate = items.compactMap { item -> (Date, MediaItem)? in
            guard let date = item.captureDate else { return nil }
            return (formatter.startOfDay(for: date), item)
        }
        let grouped = Dictionary(grouping: withDate, by: \.0)
        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let groupItems = grouped[key]?.map(\.1) ?? []
            return MediaSection(id: key, label: formatter.label(for: key), items: groupItems)
        }
    }
}
