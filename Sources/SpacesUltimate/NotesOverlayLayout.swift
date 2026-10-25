import AppKit

/// One layout decision per display, always measured against its single-row layout.
@MainActor
struct NotesOverlayLayout {
    static let horizontalInsets: CGFloat = 24
    static let cardSpacing: CGFloat = 10
    static let fontReferenceCardWidth: CGFloat = 188
    static let closeButtonWidth: CGFloat = 42
    static let closeButtonSpacing: CGFloat = 8
    static let verticalInsets: CGFloat = 12
    static let rowSpacing: CGFloat = 8
    static let navigationButtonSize: CGFloat = 24
    static let navigationButtonSpacing: CGFloat = 4
    static let minimumCompactCardHeight: CGFloat = 40
    static let activeHighlightRefreshInterval: TimeInterval = 0.25

    let rowCount: Int
    let labelWidth: CGFloat
    let rows: [[Int]]
    let minimumSingleRowNameFraction: CGFloat

    var hasCompactNavigationButton: Bool { rowCount == 2 }
    var navigationWidth: CGFloat {
        hasCompactNavigationButton ? Self.navigationButtonSize + Self.navigationButtonSpacing : 0
    }
    var cardWidth: CGFloat { labelWidth + navigationWidth }
    var cardPitch: CGFloat { cardWidth + Self.cardSpacing }

    init(spaces: [SpaceMetadata], availableWidth: CGFloat) {
        let count = max(1, spaces.count)
        let area = max(1, availableWidth - Self.horizontalInsets - Self.closeButtonWidth - Self.closeButtonSpacing)
        let singleWidth = Self.cardWidth(cardAreaWidth: area, slots: CGFloat(count))
        let minimumFraction = spaces.map {
            Self.visibleNameFraction(for: $0, cardWidth: singleWidth)
        }.min() ?? 1
        // Alternating cards go on the lower row, offset by half a card's pitch.
        let staggeredSlots = max(CGFloat((count + 1) / 2), CGFloat(count / 2) + 0.5)
        let navigationWidth = Self.navigationButtonSize + Self.navigationButtonSpacing
        let doubleWidth = Self.cardWidth(cardAreaWidth: area - staggeredSlots * navigationWidth, slots: staggeredSlots)
        let chosenRowCount = count > 1 && singleWidth < Self.fontReferenceCardWidth && minimumFraction < 0.5 && doubleWidth > singleWidth ? 2 : 1
        rowCount = chosenRowCount
        labelWidth = chosenRowCount == 2 ? doubleWidth : singleWidth
        minimumSingleRowNameFraction = minimumFraction
        rows = (0..<chosenRowCount).map { row in
            Array(stride(from: row, to: spaces.count, by: chosenRowCount))
        }
    }

    static func panelWidth(visibleWidth: CGFloat, spaceCount: Int) -> CGFloat {
        let available = max(1, visibleWidth - 32)
        return available
    }

    func panelFrame(visibleFrame: NSRect, width: CGFloat, baseHeight: Double) -> NSRect {
        let topInset: CGFloat = 132
        let base = max(CGFloat(baseHeight), CGFloat(AppSettings.minimumNotesOverlayHeightPixels))
        // Compact buttons remove the Go text row. Keep enough room for the large number
        // and a name plus a note even at the lowest configured height.
        let requestedHeight = hasCompactNavigationButton
            ? max(base * 2 - 24, Self.minimumCompactCardHeight * 2 + Self.verticalInsets + Self.rowSpacing)
            : base
        let height = min(requestedHeight, max(1, visibleFrame.height - topInset - 16))
        return NSRect(x: visibleFrame.midX - width / 2, y: visibleFrame.maxY - topInset - height,
                      width: width, height: height)
    }

    func leadingOffset(for row: Int, cardAreaWidth: CGFloat) -> CGFloat {
        let pitch = cardPitch
        let usedWidth = rows.enumerated().map { rowIndex, indices in
            CGFloat(indices.count) * pitch - Self.cardSpacing + (rowIndex == 1 ? pitch / 2 : 0)
        }.max() ?? 0
        let centering = rowCount == 2 ? max(0, (cardAreaWidth - usedWidth) / 2) : 0
        return centering + (row == 1 ? pitch / 2 : 0)
    }

    static func scaledFontSize(cardWidth: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let progress = max(0, min(1, (cardWidth - 80) / (fontReferenceCardWidth - 80)))
        return minimum + (maximum - minimum) * progress
    }

    static func numberFont(cardWidth: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: scaledFontSize(cardWidth: cardWidth, minimum: 22, maximum: 28), weight: .bold)
    }

    static func numberWidth(orderIndex: Int, cardWidth: CGFloat) -> CGFloat {
        let digits = String(repeating: "8", count: max(2, String(orderIndex).count))
        return ceil((digits as NSString).size(withAttributes: [.font: numberFont(cardWidth: cardWidth)]).width) + 4
    }

    static func titleFont(cardWidth: CGFloat) -> NSFont {
        .systemFont(ofSize: scaledFontSize(cardWidth: cardWidth, minimum: 11, maximum: 15), weight: .semibold)
    }

    static func textColumnWidth(orderIndex: Int, cardWidth: CGFloat) -> CGFloat {
        max(1, cardWidth - 20 - numberWidth(orderIndex: orderIndex, cardWidth: cardWidth) - 8)
    }

    static func visibleNameFraction(for space: SpaceMetadata, cardWidth: CGFloat) -> CGFloat {
        let font = titleFont(cardWidth: cardWidth)
        let name = space.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? space.desktopLabel : space.name
        let nameWidth = (name as NSString).size(withAttributes: [.font: font]).width
        guard nameWidth > 0 else { return 1 }
        let prefix = space.icon.isEmpty ? "" : "\(space.icon) "
        let prefixWidth = (prefix as NSString).size(withAttributes: [.font: font]).width
        // NSTextField has horizontal text insets; a truncated title also needs its ellipsis.
        let available = max(0, textColumnWidth(orderIndex: space.orderIndex, cardWidth: cardWidth) - 4 - prefixWidth)
        if available >= nameWidth { return 1 }
        let ellipsisWidth = ("…" as NSString).size(withAttributes: [.font: font]).width
        return max(0, available - ellipsisWidth) / nameWidth
    }

    private static func cardWidth(cardAreaWidth: CGFloat, slots: CGFloat) -> CGFloat {
        max(1, floor((cardAreaWidth - (slots - 1) * cardSpacing) / slots))
    }
}
