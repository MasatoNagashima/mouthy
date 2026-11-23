import Foundation

public enum StudyCalendar {
    public static func tokyo() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3600)!
        calendar.firstWeekday = 1
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    public static func dayKey(_ date: Date, calendar: Calendar = tokyo()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 今日、または昨日まで、会話が1回以上あった日が続いた数。日本時間。
    public static func streak(practiceDays: Set<String>, today: Date, calendar: Calendar = tokyo()) -> Int {
        var cursor = today
        if !practiceDays.contains(dayKey(cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  practiceDays.contains(dayKey(yesterday, calendar: calendar))
            else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while practiceDays.contains(dayKey(cursor, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// 1回 / 2回 / 3回以上。0 は練習していない日。
    public static func intensity(sessionCount: Int) -> Int {
        if sessionCount <= 0 { return 0 }
        return min(sessionCount, 3)
    }

    public struct Cell: Equatable, Sendable {
        public var day: Int?
        public var key: String?
        public var isToday: Bool
        public var isFuture: Bool
    }

    public struct Month: Equatable, Sendable {
        public var year: Int
        public var month: Int
        public var cells: [Cell]
    }

    /// 日曜始まり。前月の日は空セル。未来の月は作らない想定で、呼び出し側が止める。
    public static func month(_ year: Int, _ month: Int, today: Date, calendar: Calendar = tokyo()) -> Month {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.hour = 12
        guard let first = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: first)
        else {
            return Month(year: year, month: month, cells: [])
        }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let todayKey = dayKey(today, calendar: calendar)
        var cells = Array(repeating: Cell(day: nil, key: nil, isToday: false, isFuture: false), count: leading)
        for day in range {
            components.day = day
            let date = calendar.date(from: components) ?? first
            let key = dayKey(date, calendar: calendar)
            cells.append(Cell(day: day, key: key, isToday: key == todayKey, isFuture: key > todayKey))
        }
        return Month(year: year, month: month, cells: cells)
    }

    public static func canMoveForward(year: Int, month: Int, today: Date, calendar: Calendar = tokyo()) -> Bool {
        let parts = calendar.dateComponents([.year, .month], from: today)
        let current = (parts.year ?? 0) * 12 + (parts.month ?? 0)
        return year * 12 + month < current
    }
}
