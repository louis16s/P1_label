import CoreGraphics

enum CanvasLayout {
    static let paperPadding = 28.0
    static let noScrollZoom = 1.1
    static let roundingSafety = 2.0

    static func fitScale(viewport: CGSize, paper: PaperSize) -> Double {
        let paperWidth = safeDimension(paper.widthMM)
        let paperHeight = safeDimension(paper.heightMM)
        let usableWidth = max(
            1,
            viewport.width - paperPadding * 2 - roundingSafety
        )
        let usableHeight = max(
            1,
            viewport.height - paperPadding * 2 - roundingSafety
        )
        return max(0.1, min(
            usableWidth / (paperWidth * noScrollZoom),
            usableHeight / (paperHeight * noScrollZoom)
        ))
    }

    static func contentSize(viewport: CGSize, paper: PaperSize, scale: Double) -> CGSize {
        let paperWidth = safeDimension(paper.widthMM)
        let paperHeight = safeDimension(paper.heightMM)
        let safeScale = scale.isFinite ? max(0.1, scale) : 1
        return CGSize(
            width: max(viewport.width, paperWidth * safeScale + paperPadding * 2),
            height: max(viewport.height, paperHeight * safeScale + paperPadding * 2)
        )
    }

    private static func safeDimension(_ value: Double) -> Double {
        guard value.isFinite else { return 0.1 }
        let maximum = Double(P1PrintGeometry.maximumPageHeightDots)
            / P1PrintGeometry.dotsPerMillimeter
        return min(maximum, max(0.1, value))
    }
}
