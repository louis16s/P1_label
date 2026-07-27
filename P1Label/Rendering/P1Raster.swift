import Foundation

struct P1Raster: Equatable {
    let width: Int
    let height: Int
    /// One bit per dot, most significant bit first. `true` represents thermal ink.
    private(set) var dots: [Bool]

    init(width: Int, height: Int, fill: Bool = false) {
        precondition(width > 0 && height > 0)
        self.width = width
        self.height = height
        self.dots = Array(repeating: fill, count: width * height)
    }

    subscript(x: Int, y: Int) -> Bool {
        get { dots[y * width + x] }
        set { dots[y * width + x] = newValue }
    }

    func packedRows() -> [Data] {
        precondition(width.isMultiple(of: 8), "P1 rows must be byte aligned")
        return (0..<height).map { y in
            var row = Data(repeating: 0, count: width / 8)
            for x in 0..<width where self[x, y] {
                row[x / 8] |= UInt8(1 << (7 - (x % 8)))
            }
            return row
        }
    }

    func offsetBy(x offsetX: Int, y offsetY: Int) -> P1Raster {
        var result = P1Raster(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                let targetX = x + offsetX
                let targetY = y + offsetY
                if result.dots.indices.contains(targetY * width + targetX),
                   targetX >= 0, targetX < width, targetY >= 0, targetY < height {
                    result[targetX, targetY] = true
                }
            }
        }
        return result
    }

    func inverted() -> P1Raster {
        var result = P1Raster(width: width, height: height)
        for index in dots.indices {
            result.dots[index] = !dots[index]
        }
        return result
    }

    static func calibrationSheet(width: Int, height: Int) -> P1Raster {
        var raster = P1Raster(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where x < 2 || y < 2 || x >= width - 2 || y >= height - 2 || (x / 16 + y / 16).isMultiple(of: 2) {
                raster[x, y] = true
            }
        }
        return raster
    }

    /// A camera-readable positioning target for measuring the printer against
    /// the physical paper edges. The paper is right-aligned on the P1's
    /// 48-millimeter print head, matching the normal document rasterizer.
    static func positioningCalibrationSheet(
        width: Int,
        paperWidth: Int,
        height: Int
    ) -> P1Raster {
        var raster = P1Raster(width: width, height: height)
        let safePaperWidth = min(width, max(64, paperWidth))
        let paperLeft = width - safePaperWidth
        let inset = 8 // 1 mm at 8 dots/mm
        let left = paperLeft + inset
        let right = width - inset - 1
        let top = inset
        let bottom = height - inset - 1
        guard right - left >= 64, bottom - top >= 64 else {
            return calibrationSheet(width: width, height: height)
        }

        raster.strokeRectangle(
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            thickness: 2
        )

        // Five-millimeter ruler ticks make scale and non-linear feed error
        // measurable after perspective correction.
        for x in stride(from: paperLeft + 40, to: width, by: 40) {
            guard x < right else { break }
            raster.fillRectangle(x: x, y: top, width: 2, height: 8)
            raster.fillRectangle(x: x, y: bottom - 7, width: 2, height: 8)
        }
        for y in stride(from: 40, to: height, by: 40) {
            guard y < bottom else { break }
            raster.fillRectangle(x: left, y: y, width: 8, height: 2)
            raster.fillRectangle(x: right - 7, y: y, width: 8, height: 2)
        }

        let markerSize = 20
        let markerInset = 8
        let markerLeft = left + markerInset
        let markerRight = right - markerInset - markerSize + 1
        let markerTop = top + markerInset
        let markerBottom = bottom - markerInset - markerSize + 1

        raster.drawMarker(
            atX: markerLeft,
            y: markerTop,
            pattern: [
                true, false, false,
                false, true, false,
                false, false, true
            ]
        )
        raster.drawMarker(
            atX: markerRight,
            y: markerTop,
            pattern: [
                true, true, true,
                false, false, true,
                false, false, true
            ]
        )
        raster.drawMarker(
            atX: markerLeft,
            y: markerBottom,
            pattern: [
                true, false, true,
                false, true, false,
                true, false, true
            ]
        )
        raster.drawMarker(
            atX: markerRight,
            y: markerBottom,
            pattern: [
                true, true, false,
                true, true, false,
                false, false, true
            ]
        )

        let centerX = paperLeft + safePaperWidth / 2
        let centerY = height / 2
        raster.fillRectangle(x: centerX - 28, y: centerY, width: 57, height: 2)
        raster.fillRectangle(x: centerX, y: centerY - 28, width: 2, height: 57)
        raster.fillRectangle(x: centerX - 3, y: centerY - 3, width: 8, height: 8)
        return raster
    }

    private mutating func strokeRectangle(
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        thickness: Int
    ) {
        fillRectangle(x: left, y: top, width: right - left + 1, height: thickness)
        fillRectangle(x: left, y: bottom - thickness + 1, width: right - left + 1, height: thickness)
        fillRectangle(x: left, y: top, width: thickness, height: bottom - top + 1)
        fillRectangle(x: right - thickness + 1, y: top, width: thickness, height: bottom - top + 1)
    }

    private mutating func drawMarker(atX x: Int, y: Int, pattern: [Bool]) {
        let cell = 4
        let side = 5
        for row in 0..<side {
            for column in 0..<side {
                let isBorder = row == 0 || column == 0 || row == side - 1 || column == side - 1
                let isDataCell = !isBorder && pattern[(row - 1) * 3 + column - 1]
                if isBorder || isDataCell {
                    fillRectangle(
                        x: x + column * cell,
                        y: y + row * cell,
                        width: cell,
                        height: cell
                    )
                }
            }
        }
    }

    private mutating func fillRectangle(x: Int, y: Int, width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        let minX = max(0, x)
        let maxX = min(self.width, x + width)
        let minY = max(0, y)
        let maxY = min(self.height, y + height)
        guard minX < maxX, minY < maxY else { return }
        for targetY in minY..<maxY {
            for targetX in minX..<maxX {
                self[targetX, targetY] = true
            }
        }
    }
}
