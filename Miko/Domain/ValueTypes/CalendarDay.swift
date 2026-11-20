import Foundation

/// Timezone-safe calendar helpers for streak/daily-goal logic. All
/// "is same day" / "is yesterday" comparisons use the user's local
/// calendar at the second granularity, never relying on time portions.
enum CalendarDay {

    /// Returns the user's current local calendar.
    static var current: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal
    }

    /// Local "today" truncated to start of day.
    static func today(now: Date = Date()) -> Date {
        current.startOfDay(for: now)
    }

    /// True when `a` and `b` fall on the same local calendar day.
    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        current.isDate(a, inSameDayAs: b)
    }

    /// True when `b` is the local calendar day immediately after `a`.
    static func isNextDay(_ a: Date, _ b: Date) -> Bool {
        guard let dayAfter = current.date(byAdding: .day, value: 1, to: current.startOfDay(for: a)) else {
            return false
        }
        return isSameDay(dayAfter, b)
    }

    /// Returns the number of whole local days from `a` to `b` (positive when
    /// `b` is later). Used to detect gaps > 1 day for streak resets.
    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        let startA = current.startOfDay(for: a)
        let startB = current.startOfDay(for: b)
        return current.dateComponents([.day], from: startA, to: startB).day ?? 0
    }
}
