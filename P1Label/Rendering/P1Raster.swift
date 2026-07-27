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
}
