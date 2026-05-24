import Foundation

enum NumberFormat {
    static func compact(_ value: Int) -> String {
        let number = Double(value)
        if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        }
        if number >= 1_000 {
            return String(format: "%.0fK", number / 1_000)
        }
        return "\(value)"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func percentPrecise(_ value: Double) -> String {
        if value < 10 {
            return String(format: "%.1f%%", value)
        }
        return percent(value)
    }
}

enum TimeFormat {
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let exactShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy HH:mm")
        return formatter
    }()

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return "No activity"
        }
        if date == Date.distantPast {
            return "Loading"
        }

        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 {
            return "Just now"
        }
        if seconds < 60 * 60 {
            return "\(seconds / 60)m ago"
        }
        if seconds < 24 * 60 * 60 {
            return "\(seconds / 3600)h ago"
        }
        return dateTime.string(from: date)
    }

    static func reset(_ date: Date?) -> String {
        guard let date else {
            return "No active window"
        }
        return exactShort.string(from: date)
    }

    static func exact(_ date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }
        return exactShort.string(from: date)
    }

    static func remaining(until date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return "No active window"
        }

        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 {
            return "now"
        }
        return compactDuration(seconds: seconds)
    }

    static func compactDuration(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            if remainingMinutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remainingMinutes)m"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours == 0 {
            return "\(days)d"
        }
        return "\(days)d \(remainingHours)h"
    }
}
