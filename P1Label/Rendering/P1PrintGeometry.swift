import Foundation

enum P1PrintGeometry {
    static let dotsPerMillimeter = 8.0
    static let maximumWidthDots = P1Protocol.printWidthBytes * 8
    static let maximumPageHeightDots = 0x3FFF

    static func dots(forMillimeters value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let scaled = (value * dotsPerMillimeter).rounded(.toNearestOrAwayFromZero)
        guard scaled.isFinite else { return value.sign == .minus ? Int.min : Int.max }
        if scaled >= Double(Int.max) { return Int.max }
        if scaled <= Double(Int.min) { return Int.min }
        return Int(scaled)
    }

    static func normalizedOffsetMM(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let rounded = (min(10, max(-10, value)) * 10).rounded() / 10
        return abs(rounded) < 0.000_1 ? 0 : rounded
    }

    static func supports(_ paper: PaperSize) -> Bool {
        guard paper.widthMM.isFinite,
              paper.heightMM.isFinite,
              paper.widthMM > 0,
              paper.heightMM > 0 else {
            return false
        }
        let width = dots(forMillimeters: paper.widthMM)
        let height = dots(forMillimeters: paper.heightMM)
        return (1...maximumWidthDots).contains(width)
            && (1...maximumPageHeightDots).contains(height)
    }
}
