import CoreGraphics

enum CanvasLayout {
    static let paperPadding = 28.0
    static let noScrollZoom = 1.1
    static let roundingSafety = 2.0

    static func fitScale(viewport: CGSize, paper: PaperSize) -> Double {
        let usableWidth = max(
            1,
            viewport.width - paperPadding * 2 - roundingSafety
        )
        let usableHeight = max(
            1,
            viewport.height - paperPadding * 2 - roundingSafety
        )
        return max(0.1, min(
            usableWidth / (paper.widthMM * noScrollZoom),
            usableHeight / (paper.heightMM * noScrollZoom)
        ))
    }

    static func contentSize(viewport: CGSize, paper: PaperSize, scale: Double) -> CGSize {
        CGSize(
            width: max(viewport.width, paper.widthMM * scale + paperPadding * 2),
            height: max(viewport.height, paper.heightMM * scale + paperPadding * 2)
        )
    }
}
