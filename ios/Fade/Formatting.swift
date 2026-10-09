import Foundation

/// Small, pure text helpers for dates, so they can be tested without a screen.
enum RelativeTime {
    /// "now", "4m", "3h", "2d", or "Oct 9" once it's more than a week old.
    static func short(from date: Date, to now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        if seconds < 7 * 86_400 { return "\(seconds / 86_400)d" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// "21h" or "35m" until a vote closes. "closed" if it already has.
    static func remaining(until date: Date, from now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "closed" }
        if seconds < 3600 { return "\(max(1, seconds / 60))m" }
        if seconds < 2 * 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }
}

enum GameTime {
    /// "Tonight 7:00 PM", "Today 1:05 PM", "Tomorrow 3:00 PM", "Sat 7:30 PM", "Oct 14, 7:00 PM"
    static func label(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateFormat = "h:mm a"
        let clock = time.string(from: date)

        if calendar.isDate(date, inSameDayAs: now) {
            let hour = calendar.component(.hour, from: date)
            return (hour >= 17 ? "Tonight " : "Today ") + clock
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow " + clock
        }
        let startOfToday = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: date)).day ?? 99
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        if days > 1 && days < 7 {
            day.dateFormat = "EEE"
            return day.string(from: date) + " " + clock
        }
        day.dateFormat = "MMM d"
        return day.string(from: date) + ", " + clock
    }

    /// "Today", "Tomorrow", "Saturday, Oct 11" — section titles for a list of games.
    static func dayTitle(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "EEEE, MMM d"
        return format.string(from: date)
    }
}

/// Avatar letters and colours. Pure, so the same name gets the same colour on every launch.
enum AvatarPalette {
    /// Six hues of one lightness (from the design canvas).
    static let hues: [UInt32] = [0x4F8CFF, 0x2CC4B0, 0xA98BFF, 0xB4D957, 0xFFA45C, 0xFF86B0]

    private static func clean(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased()
    }

    /// Adds up the letters instead of using `hashValue`, which changes every launch.
    static func hue(for name: String) -> UInt32 {
        var h: UInt32 = 5381
        for scalar in clean(name).unicodeScalars { h = (h &* 33) &+ scalar.value }
        return hues[Int(h % UInt32(hues.count))]
    }

    /// "maya" → "M", "dylan" with count 2 → "DY". "?" if there is nothing to show.
    static func initials(_ name: String, count: Int = 1) -> String {
        let letters = clean(name).filter { $0.isLetter || $0.isNumber }
        if letters.isEmpty { return "?" }
        return String(letters.prefix(count)).uppercased()
    }

    /// "College Boys" → "CB", "Fam" → "FA", "Work Pool League" → "WP".
    static func groupInitials(_ name: String) -> String {
        let words = name.split(separator: " ").filter { word in word.contains { $0.isLetter || $0.isNumber } }
        if words.count >= 2, let a = words[0].first, let b = words[1].first { return String([a, b]).uppercased() }
        return initials(name, count: 2)
    }
}
