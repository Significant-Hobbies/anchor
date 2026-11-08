import Foundation

/// Turning domain values into the strings every surface shows.
///
/// Lives here rather than in the UI layer because it is pure, it is used
/// identically by the Mac, the phone, the watch and the menu bar, and because
/// down here it can actually be tested.
public enum Format {
    /// The big clock. Hours only appear once they exist, so a 25-minute session
    /// reads "24:59" rather than "0:24:59".
    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Compact durations for analytics: "1h 20m", "45m", "30s".
    public static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.rounded()))
        if total < 60 { return "\(total)s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    public static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    public static func hour(_ hour: Int) -> String {
        let components = DateComponents(hour: hour)
        guard let date = Calendar.current.date(from: components) else { return "\(hour)" }
        return date.formatted(.dateTime.hour())
    }
}
