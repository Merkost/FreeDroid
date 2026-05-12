import Foundation
import Testing
import FreeDroidDomain
@testable import Gallery

@Suite("MediaGrouper")
struct MediaGrouperTests {
    @Test func groupsByDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let items = [
            item(now, name: "a"),
            item(now.addingTimeInterval(3600), name: "b"),
            item(yesterday, name: "c")
        ]
        let formatter = GalleryDateFormatter(calendar: calendar, now: { now })
        let grouper = MediaGrouper(formatter: formatter)
        let sections = grouper.group(items)
        #expect(sections.count == 2)
        #expect(sections[0].label == "Today")
        #expect(sections[0].items.count == 2)
        #expect(sections[1].label == "Yesterday")
    }

    private func item(_ date: Date, name: String) -> MediaItem {
        MediaItem(
            id: name,
            path: RemotePath(raw: "/x/\(name)"),
            kind: .image,
            captureDate: date,
            sizeBytes: 100
        )
    }
}
