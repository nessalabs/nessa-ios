import Foundation

public enum CalendarCurrentDateResolver {
    public static func dayID(for date: Date = Date(), calendar: Calendar = defaultCalendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(year)-\(monthKey(forMonthNumber: month))-\(day)"
    }

    public static func monthKey(for date: Date = Date(), calendar: Calendar = defaultCalendar) -> String {
        monthKey(forMonthNumber: calendar.component(.month, from: date))
    }

    public static let defaultCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    public static func monthKey(forMonthNumber month: Int) -> String {
        monthKeys[max(0, min(month - 1, 11))]
    }

    private static let monthKeys = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
}

