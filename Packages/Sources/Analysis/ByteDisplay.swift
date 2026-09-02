/// 1024-based size labels (`B` / `KiB` / `MiB` / `GiB` / `TiB`). ASCII, locale-independent.
public enum ByteDisplay: Sendable {
    public static func string(_ bytes: Int64) -> String {
        guard bytes > 0 else {
            return "0 B"
        }
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let units = ["KiB", "MiB", "GiB", "TiB"]
        var value = Double(bytes) / 1024
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return "\(trimmed(value)) \(units[unit])"
    }

    public static func filesWord(_ count: Int) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }

    public static func hashUniqueLabel(_ bytes: Int64?) -> String {
        guard let bytes else {
            return "—"
        }
        return string(bytes)
    }

    private static func trimmed(_ value: Double) -> String {
        let hundredths = Int((value * 100).rounded())
        let whole = hundredths / 100
        let fraction = hundredths % 100
        if fraction == 0 {
            return "\(whole)"
        }
        if fraction % 10 == 0 {
            return "\(whole).\(fraction / 10)"
        }
        let tens = fraction / 10
        let ones = fraction % 10
        return "\(whole).\(tens)\(ones)"
    }
}
