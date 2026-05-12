import Foundation
import Testing
@testable import Gallery

@Suite("GalleryDateFormatter")
struct GalleryDateFormatterTests {
    @Test func todayLabel() {
        let formatter = GalleryDateFormatter(
            calendar: Calendar(identifier: .gregorian),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(formatter.label(for: today) == "Today")
    }

    @Test func yesterdayLabel() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let formatter = GalleryDateFormatter(calendar: calendar, now: { now })
        #expect(formatter.label(for: yesterday) == "Yesterday")
    }
}
