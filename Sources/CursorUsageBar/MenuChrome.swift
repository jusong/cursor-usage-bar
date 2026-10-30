import AppKit
import CursorUsageCore

enum MenuMetrics {
    static let width: CGFloat = 408
}

enum Mark {
    static func image(pointSize: CGFloat) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect)
            return true
        }
        return image
    }

    static func draw(in rect: NSRect) {
        let background = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
        NSColor(srgbRed: 0.11, green: 0.13, blue: 0.16, alpha: 1).setFill()
        background.fill()

        let field = rect.insetBy(dx: rect.width * 0.24, dy: rect.height * 0.22)
        let barWidth = field.width * 0.38
        let gap = field.width - barWidth * 2
        bar(
            in: NSRect(x: field.minX, y: field.minY, width: barWidth, height: field.height * 0.92),
            color: NSColor(srgbRed: 0.18, green: 0.78, blue: 0.42, alpha: 1)
        )
        bar(
            in: NSRect(x: field.minX + barWidth + gap, y: field.minY, width: barWidth, height: field.height * 0.62),
            color: NSColor(srgbRed: 1, green: 0.62, blue: 0.16, alpha: 1)
        )
    }

    private static func bar(in rect: NSRect, color: NSColor) {
        let radius = rect.width / 2
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}

enum UsageTint {
    case cursor
    case other

    var color: NSColor {
        switch self {
        case .cursor: return .systemGreen
        case .other: return .systemOrange
        }
    }
}

struct UsageLine {
    enum Kind {
        case pool
        case model
        case note
    }

    var name: String
    var tokens: String?
    var percent: String?
    var kind: Kind
    var tint: UsageTint? = nil
}

enum StatusReadout {
    static func value(percent: Double, tokens: Int?, mode: DisplayMode) -> String {
        switch mode {
        case .percent:
            return UsageText.barPercent(percent)
        case .tokens:
            return tokens.map(UsageText.barTokens) ?? "—"
        case .percentAndTokens:
            let amount = tokens.map(UsageText.barTokens) ?? "—"
            return "\(amount) \(UsageText.barPercent(percent))"
        }
    }
}

final class StatusColumnsView: NSView {
    struct Column {
        var label: String
        var value: String
        var tint: UsageTint
    }

    var columns: [Column] = [] {
        didSet { needsDisplay = true }
    }

    var plain: String? {
        didSet { needsDisplay = true }
    }

    private let logo = Mark.image(pointSize: 32)

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func preferredWidth() -> CGFloat {
        metrics(height: NSStatusBar.system.thickness).width
    }

    override func draw(_ dirtyRect: NSRect) {
        let layout = metrics(height: bounds.height)
        if showsLogo {
            logo.draw(
                in: layout.logo,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
        if let plain {
            let text = NSAttributedString(string: plain, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ])
            let size = text.size()
            let y = (bounds.height - size.height) / 2
            text.draw(in: NSRect(x: layout.logo.maxX + 4, y: y, width: size.width + 2, height: size.height))
            return
        }
        for column in layout.columns {
            draw(column.label, font: layout.labelFont, color: .labelColor, in: column.labelFrame)
            draw(column.value, font: layout.valueFont, color: column.tint.color, in: column.valueFrame)
        }
    }

    private var showsLogo: Bool { true }

    private struct Layout {
        var logo: NSRect
        var columns: [(label: String, value: String, tint: UsageTint, labelFrame: NSRect, valueFrame: NSRect)]
        var width: CGFloat
        var labelFont: NSFont
        var valueFont: NSFont
    }

    private func metrics(height: CGFloat) -> Layout {
        let bar = max(height, 18)
        let labelFont = NSFont.systemFont(ofSize: bar >= 24 ? 9 : 8, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: bar >= 24 ? 11 : 10, weight: .semibold)
        let logoSide = bar - 1
        let logo = NSRect(x: 1, y: (bar - logoSide) / 2, width: logoSide, height: logoSide)
        if let plain {
            let width = (plain as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]).width
            return Layout(logo: logo, columns: [], width: ceil(logo.maxX + 6 + width + 8), labelFont: labelFont, valueFont: valueFont)
        }
        let labelHeight = ceil((("A" as NSString).size(withAttributes: [.font: labelFont])).height)
        let valueHeight = ceil((("8" as NSString).size(withAttributes: [.font: valueFont])).height)
        let block = labelHeight + valueHeight
        let top = max(0, (bar - block) / 2)
        var x = logo.maxX + 6
        var placed: [(label: String, value: String, tint: UsageTint, labelFrame: NSRect, valueFrame: NSRect)] = []
        for column in columns {
            let labelWidth = ceil((column.label as NSString).size(withAttributes: [.font: labelFont]).width)
            let valueWidth = ceil((column.value as NSString).size(withAttributes: [.font: valueFont]).width)
            let width = max(labelWidth, valueWidth)
            placed.append((
                column.label,
                column.value,
                column.tint,
                NSRect(x: x, y: top, width: width, height: labelHeight),
                NSRect(x: x, y: top + labelHeight, width: width, height: valueHeight)
            ))
            x += width + 12
        }
        let width = placed.last.map { $0.valueFrame.maxX + 8 } ?? (logo.maxX + 8)
        return Layout(logo: logo, columns: placed, width: ceil(width), labelFont: labelFont, valueFont: valueFont)
    }

    private func draw(_ string: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let text = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let size = text.size()
        let frame = NSRect(
            x: rect.minX + (rect.width - size.width) / 2,
            y: rect.minY + (rect.height - size.height) / 2,
            width: size.width + 1,
            height: size.height
        )
        text.draw(in: frame)
    }
}

final class PeriodHeaderView: NSView {
    private static let billingURL = URL(string: "https://cursor.com/dashboard/billing")!

    private let period: String?
    private let periodLabel: String?
    private let message: String?
    private let warning: String?
    private let linkTitle: String
    private let icon: NSImage
    private var linkFrame = NSRect.zero

    init(period: String?, periodLabel: String?, message: String?, warning: String?, linkTitle: String) {
        self.period = period
        self.periodLabel = periodLabel
        self.message = message
        self.warning = warning
        self.linkTitle = linkTitle
        icon = Mark.image(pointSize: 32)
        let height = Self.height(hasWarning: warning != nil)
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: height))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        discardCursorRects()
        if !linkFrame.isEmpty {
            addCursorRect(linkFrame, cursor: .pointingHand)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let plate = bounds.insetBy(dx: 8, dy: 7)
        let path = NSBezierPath(roundedRect: plate, xRadius: 10, yRadius: 10)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let logo = NSRect(x: plate.minX + 10, y: plate.minY + 10, width: 32, height: 32)
        icon.draw(in: logo, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])

        let textX = logo.maxX + 10
        let textWidth = plate.maxX - 12 - textX
        let title = NSAttributedString(string: "Cursor", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        title.draw(in: NSRect(x: textX, y: plate.minY + 9, width: textWidth, height: 18))

        let subtitle = period.map { range in
            guard let periodLabel, !periodLabel.isEmpty else { return range }
            return "\(periodLabel)  \(range)"
        } ?? (message ?? "")
        let subtitleText = NSAttributedString(string: subtitle, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        subtitleText.draw(in: NSRect(x: textX, y: plate.minY + 28, width: textWidth, height: 16))

        var linkTop = plate.minY + 46
        if let warning {
            let warningText = NSAttributedString(string: warning, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.systemOrange,
            ])
            warningText.draw(in: NSRect(x: textX, y: plate.minY + 46, width: textWidth, height: 16))
            linkTop = plate.minY + 64
        }

        let link = NSAttributedString(string: linkTitle, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        let linkSize = link.size()
        linkFrame = NSRect(x: textX, y: linkTop, width: min(textWidth, linkSize.width + 2), height: 16)
        link.draw(in: linkFrame)
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if linkFrame.contains(point) {
            NSWorkspace.shared.open(Self.billingURL)
        }
        enclosingMenuItem?.menu?.cancelTracking()
    }

    private static func height(hasWarning: Bool) -> CGFloat {
        hasWarning ? 104 : 86
    }
}

final class UsageLineView: NSView {
    private let line: UsageLine

    init(line: UsageLine) {
        self.line = line
        let height: CGFloat
        switch line.kind {
        case .pool: height = 26
        case .model: height = 22
        case .note: height = 24
        }
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: height))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        switch line.kind {
        case .note:
            drawNote()
        case .pool, .model:
            drawColumns()
        }
    }

    override func mouseUp(with event: NSEvent) {
        enclosingMenuItem?.menu?.cancelTracking()
    }

    private func drawNote() {
        let text = NSAttributedString(string: line.name, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let height = text.size().height
        text.draw(in: NSRect(x: 18, y: (bounds.height - height) / 2, width: bounds.width - 36, height: height))
    }

    private func drawColumns() {
        let pool = line.kind == .pool
        let font = NSFont.monospacedDigitSystemFont(ofSize: pool ? 13 : 12, weight: pool ? .semibold : .regular)
        let nameFont = NSFont.systemFont(ofSize: pool ? 13 : 12, weight: pool ? .semibold : .regular)
        let nameColor = NSColor.labelColor
        let numberColor = line.tint?.color ?? nameColor
        if pool, let tint = line.tint {
            let dot = NSRect(x: 14, y: (bounds.height - 8) / 2, width: 8, height: 8)
            tint.color.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
        let nameX: CGFloat = pool ? 28 : 36
        let percentWidth: CGFloat = 58
        let tokenWidth: CGFloat = 92
        let right: CGFloat = 16
        let percentX = bounds.width - right - percentWidth
        let tokenX = percentX - 8 - tokenWidth
        let nameWidth = tokenX - 10 - nameX
        let sample = ("8" as NSString).size(withAttributes: [.font: font]).height
        let y = (bounds.height - sample) / 2

        let nameStyle = NSMutableParagraphStyle()
        nameStyle.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: line.name, attributes: [
            .font: nameFont,
            .foregroundColor: nameColor,
            .paragraphStyle: nameStyle,
        ]).draw(in: NSRect(x: nameX, y: y, width: nameWidth, height: sample + 1))

        let numberStyle = NSMutableParagraphStyle()
        numberStyle.alignment = .right
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: numberColor,
            .paragraphStyle: numberStyle,
        ]
        if let tokens = line.tokens {
            NSAttributedString(string: tokens, attributes: numberAttributes)
                .draw(in: NSRect(x: tokenX, y: y, width: tokenWidth, height: sample + 1))
        }
        if let percent = line.percent {
            NSAttributedString(string: percent, attributes: numberAttributes)
                .draw(in: NSRect(x: percentX, y: y, width: percentWidth, height: sample + 1))
        }
    }
}
