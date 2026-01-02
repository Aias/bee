import Foundation

enum CronParser {
    /// Converts a cron expression to human-readable English
    static func toEnglish(_ cron: String) -> String {
        let parts = cron.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return cron }

        let minute = parts[0]
        let hour = parts[1]
        let dayOfMonth = parts[2]
        let month = parts[3]
        let dayOfWeek = parts[4]

        // Every N minutes
        if minute.hasPrefix("*/"), hour == "*", dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            let interval = String(minute.dropFirst(2))
            if interval == "1" {
                return "Every minute"
            }
            return "Every \(interval) minutes"
        }

        // Every hour at specific minute
        if !minute.contains("*") && !minute.contains("/"),
           hour == "*", dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            let min = Int(minute) ?? 0
            if min == 0 {
                return "Every hour"
            }
            return "Every hour at :\(String(format: "%02d", min))"
        }

        // Daily at specific time
        if !minute.contains("*") && !minute.contains("/"),
           !hour.contains("*") && !hour.contains("/"),
           dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            return "Daily at \(formatTime(hour: hour, minute: minute))"
        }

        // Specific days of week
        if dayOfWeek != "*" && dayOfMonth == "*" && month == "*" {
            let days = parseDaysOfWeek(dayOfWeek)
            let time = formatTime(hour: hour, minute: minute)
            return "\(days) at \(time)"
        }

        // Every N hours
        if minute == "0" && hour.hasPrefix("*/"),
           dayOfMonth == "*", month == "*", dayOfWeek == "*" {
            let interval = String(hour.dropFirst(2))
            if interval == "1" {
                return "Every hour"
            }
            return "Every \(interval) hours"
        }

        return cron
    }

    private static func formatTime(hour: String, minute: String) -> String {
        guard let h = Int(hour), let m = Int(minute) else {
            return "\(hour):\(minute)"
        }
        let period = h >= 12 ? "PM" : "AM"
        let displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", displayHour, m, period)
    }

    private static func parseDaysOfWeek(_ value: String) -> String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let fullNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

        // Handle ranges like 1-5 (Mon-Fri)
        if value == "1-5" { return "Weekdays" }
        if value == "0,6" || value == "6,0" { return "Weekends" }

        // Handle comma-separated values
        let indices = value.split(separator: ",").compactMap { Int($0) }
        if indices.count == 1, let idx = indices.first, idx < fullNames.count {
            return fullNames[idx]
        }

        let names = indices.compactMap { $0 < dayNames.count ? dayNames[$0] : nil }
        return names.joined(separator: ", ")
    }
}
