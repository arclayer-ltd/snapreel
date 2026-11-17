import Foundation

/// Display formatting shared by every screen. Keep wording here so it reads the same everywhere.
enum Format {
    /// "0:07", "2:05", "1:02:05".
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Remaining time with a leading minus: "-0:31".
    static func remaining(_ seconds: Double) -> String {
        "-" + clock(max(0, seconds))
    }

    /// Spoken-style duration for metadata: "31 sec", "2 min", "1 hr 5 min".
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 sec" }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) sec" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    /// Time stamp inside a video: "Note at 0:14".
    static func stamp(_ seconds: Double) -> String { clock(seconds) }

    /// "Just now", "5m ago", "2h ago", "Yesterday", "3d ago", "12 Nov", "12 Nov 2025".
    static func age(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "\(Int(interval / 3600))h ago" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return "\(days)d ago" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? shortDate.string(from: date) : shortDateYear.string(from: date)
    }

    /// "18 Nov 2026"
    static func date(_ date: Date) -> String { mediumDate.string(from: date) }

    /// "18 Nov 2026 at 09:41"
    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

    /// "9:41"
    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    /// "48.2 MB"
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// "1920 × 1080"
    static func resolution(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "Audio only" }
        return "\(width) × \(height)"
    }

    /// Section title for a day in grouped lists: "Today", "Yesterday", "Monday", "12 November".
    static func dayTitle(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return weekday.string(from: date) }
        return dayMonth.string(from: date)
    }

    /// Default title for a new recording: "Screen recording – 18 Nov, 09:41".
    static func defaultTitle(for kind: RecordingKind, at date: Date = Date()) -> String {
        "\(kind.titlePrefix) – \(titleStamp.string(from: date))"
    }

    // MARK: Formatters

    private static let shortDate = make("d MMM")
    private static let shortDateYear = make("d MMM yyyy")
    private static let weekday = make("EEEE")
    private static let dayMonth = make("d MMMM")
    private static let titleStamp = make("d MMM, HH:mm")

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static func make(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
}
