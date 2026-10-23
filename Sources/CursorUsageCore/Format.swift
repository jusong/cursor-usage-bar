import Foundation

public enum DisplayMode: String, Equatable, Sendable {
    case percent
    case percentAndTokens
    case tokens

    public init(stored raw: String?) {
        self = raw.flatMap(DisplayMode.init(rawValue:)) ?? .percent
    }
}

public enum UsageText {
    public static func detailTokens(_ tokens: Int) -> String {
        scaled(tokens, places: 1, stripTrailingZero: true)
    }

    public static func barTokens(_ tokens: Int) -> String {
        if tokens >= 100_000_000 {
            return scaled(tokens, places: 1, stripTrailingZero: false)
        }
        return scaled(tokens, places: 0, stripTrailingZero: true)
    }

    public static func detailPercent(_ percent: Double) -> String {
        String(format: "%.1f%%", rounded(percent, places: 1))
    }

    public static func barPercent(_ percent: Double) -> String {
        String(format: "%.0f%%", percent.rounded())
    }

    public static func detailLine(tokens: Int, percent: Double) -> String {
        "\(detailTokens(tokens)) \(detailPercent(percent))"
    }

    public static func menuBar(_ snapshot: UsageSnapshot, mode: DisplayMode) -> String {
        menuBar(
            cursorPercent: snapshot.cursor.percent,
            otherPercent: snapshot.other.percent,
            cursorTokens: snapshot.cursor.tokens,
            otherTokens: snapshot.other.tokens,
            mode: mode
        )
    }

    public static func menuBar(
        cursorPercent: Double,
        otherPercent: Double,
        cursorTokens: Int?,
        otherTokens: Int?,
        mode: DisplayMode
    ) -> String {
        let cursorPct = barPercent(cursorPercent)
        let otherPct = barPercent(otherPercent)
        let cursorTok = cursorTokens.map(barTokens) ?? "—"
        let otherTok = otherTokens.map(barTokens) ?? "—"
        switch mode {
        case .percent:
            return "Cursor \(cursorPct) · Other \(otherPct)"
        case .percentAndTokens:
            return "Cursor \(cursorTok) \(cursorPct) · Other \(otherTok) \(otherPct)"
        case .tokens:
            return "Cursor \(cursorTok) · Other \(otherTok)"
        }
    }

    public static func cycle(_ start: Date, _ end: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private static func scaled(_ tokens: Int, places: Int, stripTrailingZero: Bool) -> String {
        if tokens >= 100_000_000 {
            return amount(Double(tokens) / 100_000_000, suffix: "亿", places: places, stripTrailingZero: stripTrailingZero)
        }
        if tokens >= 10_000 {
            return amount(Double(tokens) / 10_000, suffix: "万", places: places, stripTrailingZero: stripTrailingZero)
        }
        return String(tokens)
    }

    private static func amount(_ value: Double, suffix: String, places: Int, stripTrailingZero: Bool) -> String {
        let number = rounded(value, places: places)
        let text = places == 0 ? String(Int(number)) : String(format: "%.\(places)f", number)
        if stripTrailingZero, text.hasSuffix(".0") {
            return String(text.dropLast(2)) + suffix
        }
        return text + suffix
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (value * factor).rounded() / factor
    }
}
