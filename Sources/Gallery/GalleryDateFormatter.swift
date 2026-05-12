import Foundation

public struct GalleryDateFormatter: Sendable {
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    public func label(for date: Date) -> String {
        let today = now()
        if calendar.isDate(date, inSameDayAs: today) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let daysAgo = calendar.dateComponents([.day], from: date, to: today).day ?? 0
        if daysAgo < 7 {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "EEEE"
            return weekdayFormatter.string(from: date)
        }
        let longFormatter = DateFormatter()
        longFormatter.dateStyle = .long
        longFormatter.timeStyle = .none
        return longFormatter.string(from: date)
    }

    public func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}
