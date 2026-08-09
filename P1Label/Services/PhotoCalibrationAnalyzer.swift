import CoreGraphics
import Foundation
import ImageIO
import Vision

struct PhotoCalibrationResult: Equatable, Sendable {
    let horizontalOffsetMM: Double
    let verticalOffsetMM: Double
    let rotationDegrees: Double
    let confidence: Double

    var confidenceDescription: String {
        switch confidence {
        case 0.82...: "高"
        case 0.68...: "中"
        default: "低"
        }
    }

    func addingPrintedOffset(horizontal: Double, vertical: Double) -> PhotoCalibrationResult {
        PhotoCalibrationResult(
            horizontalOffsetMM: P1PrintGeometry.normalizedOffsetMM(
                horizontal + horizontalOffsetMM
            ),
            verticalOffsetMM: P1PrintGeometry.normalizedOffsetMM(
                vertical + verticalOffsetMM
            ),
            rotationDegrees: rotationDegrees,
            confidence: confidence
        )
    }
}

enum PhotoCalibrationError: LocalizedError {
    case cannotReadImage
    case paperEdgeNotFound
    case printedFrameNotFound
    case lowConfidence
    case implausibleResult

    var errorDescription: String? {
        switch self {
        case .cannotReadImage:
            "无法读取这张照片，请改用 HEIC、JPEG 或 PNG。"
        case .paperEdgeNotFound:
            "没有可靠识别到整张标签纸的四条外边。请将标签取下，单独平放在深色背景上再拍摄。"
        case .printedFrameNotFound:
            "识别到了标签纸，但没有找到定位标签的内框。请确认照片中是“打印定位标签”生成的图案。"
        case .lowConfidence:
            "纸张边缘或定位框不够清晰，本次结果未自动套用。请正对标签、避免阴影和其他标签重叠后重拍。"
        case .implausibleResult:
            "测得的偏移超出安全范围，本次结果未自动套用。请检查纸张尺寸后重新打印定位标签。"
        }
    }
}

enum PhotoCalibrationAnalyzer {
    struct Quadrilateral: Equatable, Sendable {
        let topLeft: CGPoint
        let topRight: CGPoint
        let bottomRight: CGPoint
        let bottomLeft: CGPoint

        var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
        var center: CGPoint {
            let sum = points.reduce(CGPoint.zero) { partial, point in
                CGPoint(x: partial.x + point.x, y: partial.y + point.y)
            }
            return CGPoint(x: sum.x / 4, y: sum.y / 4)
        }
        var area: Double {
            let values = points
            return abs(zip(values, values.dropFirst() + [values[0]]).reduce(0) {
                $0 + Double($1.0.x * $1.1.y - $1.1.x * $1.0.y)
            }) / 2
        }
        var averageWidth: Double {
            (topLeft.distance(to: topRight) + bottomLeft.distance(to: bottomRight)) / 2
        }
        var averageHeight: Double {
            (topLeft.distance(to: bottomLeft) + topRight.distance(to: bottomRight)) / 2
        }
    }

    static func analyze(photoURL: URL, paper: PaperSize) throws -> PhotoCalibrationResult {
        let visionOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4_096,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                visionOptions as CFDictionary
              ) else {
            throw PhotoCalibrationError.cannotReadImage
        }

        let imageAspect = Double(image.width) / Double(image.height)

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 32
        request.minimumConfidence = 0.42
        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1
        request.minimumSize = 0.035
        request.quadratureTolerance = 35

        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let observations = request.results ?? []
        guard observations.count >= 2 else {
            throw PhotoCalibrationError.paperEdgeNotFound
        }

        var candidates = observations.map {
            RectangleCandidate(
                quad: Quadrilateral(
                    topLeft: aspectCorrected($0.topLeft, imageAspect: imageAspect),
                    topRight: aspectCorrected($0.topRight, imageAspect: imageAspect),
                    bottomRight: aspectCorrected($0.bottomRight, imageAspect: imageAspect),
                    bottomLeft: aspectCorrected($0.bottomLeft, imageAspect: imageAspect)
                ),
                confidence: Double($0.confidence)
            )
        }
        let referenceFrame = candidates
            .filter {
                let aspect = $0.quad.averageWidth / max($0.quad.averageHeight, 0.000_1)
                return abs(log(aspect / (paper.widthMM / paper.heightMM))) < 0.35
            }
            .max(by: { $0.quad.area < $1.quad.area })?
            .quad
        candidates += brightPaperCandidates(
            imageSource: source,
            expectedAspect: paper.widthMM / paper.heightMM,
            around: referenceFrame
        )
        guard let pair = bestNestedPair(in: candidates, paper: paper, imageAspect: imageAspect) else {
            throw observations.isEmpty
                ? PhotoCalibrationError.paperEdgeNotFound
                : PhotoCalibrationError.printedFrameNotFound
        }

        let result = try correction(
            paper: pair.outer.quad,
            printedFrame: pair.inner.quad,
            paperSize: paper,
            detectionConfidence: sqrt(pair.outer.confidence * pair.inner.confidence)
        )
        guard result.confidence >= 0.58 else {
            throw PhotoCalibrationError.lowConfidence
        }
        return result
    }

    static func correction(
        paper: Quadrilateral,
        printedFrame: Quadrilateral,
        paperSize: PaperSize,
        detectionConfidence: Double = 1
    ) throws -> PhotoCalibrationResult {
        guard let transform = ProjectiveTransform(
            source: paper,
            destinationWidth: paperSize.widthMM,
            destinationHeight: paperSize.heightMM
        ) else {
            throw PhotoCalibrationError.paperEdgeNotFound
        }

        let topLeft = transform.apply(to: printedFrame.topLeft)
        let topRight = transform.apply(to: printedFrame.topRight)
        let bottomRight = transform.apply(to: printedFrame.bottomRight)
        let bottomLeft = transform.apply(to: printedFrame.bottomLeft)
        let center = CGPoint(
            x: (topLeft.x + topRight.x + bottomRight.x + bottomLeft.x) / 4,
            y: (topLeft.y + topRight.y + bottomRight.y + bottomLeft.y) / 4
        )

        let measuredX = Double(center.x) - paperSize.widthMM / 2
        let measuredY = Double(center.y) - paperSize.heightMM / 2
        let horizontalOffset = -measuredX
        let verticalOffset = -measuredY
        let topAngle = atan2(
            Double(topRight.y - topLeft.y),
            Double(topRight.x - topLeft.x)
        ) * 180 / .pi

        let leftInset = (Double(topLeft.x) + Double(bottomLeft.x)) / 2
        let rightInset = paperSize.widthMM - (Double(topRight.x) + Double(bottomRight.x)) / 2
        let topInset = (Double(topLeft.y) + Double(topRight.y)) / 2
        let bottomInset = paperSize.heightMM - (Double(bottomLeft.y) + Double(bottomRight.y)) / 2
        let insetError = (
            abs((leftInset + rightInset) / 2 - 1)
            + abs((topInset + bottomInset) / 2 - 1)
        ) / 2
        let geometryConfidence = max(0, 1 - insetError / 2.5 - abs(topAngle) / 12)
        let confidence = min(1, detectionConfidence * geometryConfidence)

        guard abs(horizontalOffset) <= 8, abs(verticalOffset) <= 8, abs(topAngle) <= 8 else {
            throw PhotoCalibrationError.implausibleResult
        }

        return PhotoCalibrationResult(
            horizontalOffsetMM: horizontalOffset,
            verticalOffsetMM: verticalOffset,
            rotationDegrees: topAngle,
            confidence: confidence
        )
    }

    private struct RectangleCandidate {
        let quad: Quadrilateral
        let confidence: Double
    }

    private struct RectanglePair {
        let outer: RectangleCandidate
        let inner: RectangleCandidate
        let score: Double
    }

    private static func bestNestedPair(
        in candidates: [RectangleCandidate],
        paper: PaperSize,
        imageAspect: Double
    ) -> RectanglePair? {
        let expectedAreaRatio = ((paper.widthMM - 2) * (paper.heightMM - 2))
            / (paper.widthMM * paper.heightMM)
        let expectedAspect = paper.widthMM / paper.heightMM
        var pairs: [RectanglePair] = []

        for outer in candidates where outer.quad.area / imageAspect > 0.025 {
            let outerDiagonal = hypot(outer.quad.averageWidth, outer.quad.averageHeight)
            let observedAspect = outer.quad.averageWidth / max(outer.quad.averageHeight, 0.000_1)
            let aspectError = abs(log(observedAspect / expectedAspect))
            guard aspectError < 0.55 else { continue }

            for inner in candidates where inner.quad.area < outer.quad.area {
                let areaRatio = inner.quad.area / outer.quad.area
                guard areaRatio > 0.72, areaRatio < 0.97 else { continue }
                let centerDistance = outer.quad.center.distance(to: inner.quad.center)
                guard centerDistance < outerDiagonal * 0.075 else { continue }
                guard outer.quad.contains(inner.quad, tolerance: outerDiagonal * 0.035) else { continue }

                let areaScore = max(0, 1 - abs(areaRatio - expectedAreaRatio) / 0.12)
                let centerScore = max(0, 1 - centerDistance / (outerDiagonal * 0.075))
                let aspectScore = max(0, 1 - aspectError / 0.55)
                let sizeScore = min(1, (outer.quad.area / imageAspect) / 0.18)
                let score = areaScore * 0.35
                    + centerScore * 0.25
                    + aspectScore * 0.15
                    + sizeScore * 0.15
                    + sqrt(outer.confidence * inner.confidence) * 0.10
                pairs.append(.init(outer: outer, inner: inner, score: score))
            }
        }
        return pairs.max(by: { $0.score < $1.score })
    }

    private static func aspectCorrected(_ point: CGPoint, imageAspect: Double) -> CGPoint {
        CGPoint(x: Double(point.x) * imageAspect, y: point.y)
    }

    /// Rounded label stock is deliberately not accepted by Vision's strict
    /// rectangle detector. On the dark background requested by the UI, its
    /// white outer margin is still a connected bright contour. These
    /// candidates supplement (rather than replace) Vision's printed-frame
    /// observations.
    private static func brightPaperCandidates(
        imageSource: CGImageSource,
        expectedAspect: Double,
        around referenceFrame: Quadrilateral?
    ) -> [RectangleCandidate] {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_200,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            options as CFDictionary
        ) else { return [] }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let count = width * height
        var isBright = [Bool](repeating: false, count: count)
        var histogram = [Int](repeating: 0, count: 256)
        for index in 0..<count {
            let offset = index * 4
            let luminance = (
                Int(pixels[offset]) * 299
                + Int(pixels[offset + 1]) * 587
                + Int(pixels[offset + 2]) * 114
            ) / 1000
            histogram[luminance] += 1
        }
        let brightCutoff = max(105, min(155, otsuThreshold(histogram: histogram, count: count)))
        for index in 0..<count {
            let offset = index * 4
            let luminance = (
                Int(pixels[offset]) * 299
                + Int(pixels[offset + 1]) * 587
                + Int(pixels[offset + 2]) * 114
            ) / 1000
            isBright[index] = pixels[offset + 3] > 16 && luminance >= brightCutoff
        }
        let envelopeMask = isBright
        isBright = dilated(isBright, width: width, height: height, radius: 5)

        var visited = [Bool](repeating: false, count: count)
        var results: [RectangleCandidate] = []
        let imageAspect = Double(width) / Double(height)
        let minimumComponentSize = max(80, count / 15_000)
        if let referenceFrame,
           let envelope = brightEnvelope(
                mask: envelopeMask,
                width: width,
                height: height,
                imageAspect: imageAspect,
                around: referenceFrame
           ) {
            results.append(.init(quad: envelope, confidence: 0.86))
        }

        for seed in 0..<count where isBright[seed] && !visited[seed] {
            visited[seed] = true
            var queue = [seed]
            var queueIndex = 0
            var pixelCount = 0
            var topLeft = (x: width, y: height, metric: Int.max)
            var topRight = (x: 0, y: height, metric: Int.min)
            var bottomRight = (x: 0, y: 0, metric: Int.min)
            var bottomLeft = (x: width, y: 0, metric: Int.max)

            while queueIndex < queue.count {
                let index = queue[queueIndex]
                queueIndex += 1
                pixelCount += 1
                let x = index % width
                let y = index / width
                let sum = x + y
                let difference = x - y
                if sum < topLeft.metric { topLeft = (x, y, sum) }
                if difference > topRight.metric { topRight = (x, y, difference) }
                if sum > bottomRight.metric { bottomRight = (x, y, sum) }
                if difference < bottomLeft.metric { bottomLeft = (x, y, difference) }

                if x > 0 {
                    appendBright(index - 1, isBright: isBright, visited: &visited, queue: &queue)
                }
                if x + 1 < width {
                    appendBright(index + 1, isBright: isBright, visited: &visited, queue: &queue)
                }
                if y > 0 {
                    appendBright(index - width, isBright: isBright, visited: &visited, queue: &queue)
                }
                if y + 1 < height {
                    appendBright(index + width, isBright: isBright, visited: &visited, queue: &queue)
                }
            }

            guard pixelCount >= minimumComponentSize else { continue }
            let quad = Quadrilateral(
                topLeft: normalized(bottomLeft, width: width, height: height, imageAspect: imageAspect),
                topRight: normalized(bottomRight, width: width, height: height, imageAspect: imageAspect),
                bottomRight: normalized(topRight, width: width, height: height, imageAspect: imageAspect),
                bottomLeft: normalized(topLeft, width: width, height: height, imageAspect: imageAspect)
            )
            let areaFraction = quad.area / imageAspect
            let aspect = quad.averageWidth / max(quad.averageHeight, 0.000_1)
            guard areaFraction > 0.08,
                  areaFraction < 0.85,
                  abs(log(aspect / expectedAspect)) < 0.45 else { continue }
            results.append(.init(quad: quad, confidence: 0.78))
        }
        return results
    }

    private static func brightEnvelope(
        mask: [Bool],
        width: Int,
        height: Int,
        imageAspect: Double,
        around reference: Quadrilateral
    ) -> Quadrilateral? {
        let referenceX = reference.points.map { Double($0.x) / imageAspect * Double(width) }
        let referenceY = reference.points.map { Double($0.y) * Double(height) }
        guard let minimumReferenceX = referenceX.min(),
              let maximumReferenceX = referenceX.max(),
              let minimumReferenceY = referenceY.min(),
              let maximumReferenceY = referenceY.max() else { return nil }
        let expansionX = (maximumReferenceX - minimumReferenceX) * 0.10
        let expansionY = (maximumReferenceY - minimumReferenceY) * 0.10
        let minimumX = max(0, Int((minimumReferenceX - expansionX).rounded(.down)))
        let maximumX = min(width - 1, Int((maximumReferenceX + expansionX).rounded(.up)))
        let minimumY = max(0, Int((minimumReferenceY - expansionY).rounded(.down)))
        let maximumY = min(height - 1, Int((maximumReferenceY + expansionY).rounded(.up)))

        var topLeft = (x: width, y: height, metric: Int.max)
        var topRight = (x: 0, y: height, metric: Int.min)
        var bottomRight = (x: 0, y: 0, metric: Int.min)
        var bottomLeft = (x: width, y: 0, metric: Int.max)
        var found = 0
        for y in minimumY...maximumY {
            for x in minimumX...maximumX where mask[y * width + x] {
                found += 1
                let sum = x + y
                let difference = x - y
                if sum < topLeft.metric { topLeft = (x, y, sum) }
                if difference > topRight.metric { topRight = (x, y, difference) }
                if sum > bottomRight.metric { bottomRight = (x, y, sum) }
                if difference < bottomLeft.metric { bottomLeft = (x, y, difference) }
            }
        }
        guard found > 100 else { return nil }
        return Quadrilateral(
            topLeft: normalized(bottomLeft, width: width, height: height, imageAspect: imageAspect),
            topRight: normalized(bottomRight, width: width, height: height, imageAspect: imageAspect),
            bottomRight: normalized(topRight, width: width, height: height, imageAspect: imageAspect),
            bottomLeft: normalized(topLeft, width: width, height: height, imageAspect: imageAspect)
        )
    }

    private static func appendBright(
        _ index: Int,
        isBright: [Bool],
        visited: inout [Bool],
        queue: inout [Int]
    ) {
        guard isBright[index], !visited[index] else { return }
        visited[index] = true
        queue.append(index)
    }

    private static func dilated(
        _ source: [Bool],
        width: Int,
        height: Int,
        radius: Int
    ) -> [Bool] {
        var horizontal = [Bool](repeating: false, count: source.count)
        for y in 0..<height {
            for x in 0..<width where source[y * width + x] {
                for targetX in max(0, x - radius)...min(width - 1, x + radius) {
                    horizontal[y * width + targetX] = true
                }
            }
        }
        var result = [Bool](repeating: false, count: source.count)
        for y in 0..<height {
            for x in 0..<width where horizontal[y * width + x] {
                for targetY in max(0, y - radius)...min(height - 1, y + radius) {
                    result[targetY * width + x] = true
                }
            }
        }
        return result
    }

    private static func normalized(
        _ point: (x: Int, y: Int, metric: Int),
        width: Int,
        height: Int,
        imageAspect: Double
    ) -> CGPoint {
        CGPoint(
            x: (Double(point.x) / Double(width)) * imageAspect,
            y: Double(point.y) / Double(height)
        )
    }

    private static func otsuThreshold(histogram: [Int], count: Int) -> Int {
        let weightedTotal = histogram.enumerated().reduce(0.0) {
            $0 + Double($1.offset * $1.element)
        }
        var backgroundCount = 0.0
        var backgroundWeighted = 0.0
        var bestVariance = -1.0
        var bestLevel = 160
        for level in histogram.indices {
            backgroundCount += Double(histogram[level])
            guard backgroundCount > 0 else { continue }
            let foregroundCount = Double(count) - backgroundCount
            guard foregroundCount > 0 else { break }
            backgroundWeighted += Double(level * histogram[level])
            let backgroundMean = backgroundWeighted / backgroundCount
            let foregroundMean = (weightedTotal - backgroundWeighted) / foregroundCount
            let difference = backgroundMean - foregroundMean
            let variance = backgroundCount * foregroundCount * difference * difference
            if variance > bestVariance {
                bestVariance = variance
                bestLevel = level
            }
        }
        return bestLevel
    }

    private struct ProjectiveTransform {
        let coefficients: [Double]

        init?(source: Quadrilateral, destinationWidth: Double, destinationHeight: Double) {
            let destination = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: destinationWidth, y: 0),
                CGPoint(x: destinationWidth, y: destinationHeight),
                CGPoint(x: 0, y: destinationHeight)
            ]
            var matrix = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)
            for (index, pair) in zip(source.points, destination).enumerated() {
                let x = Double(pair.0.x)
                let y = Double(pair.0.y)
                let u = Double(pair.1.x)
                let v = Double(pair.1.y)
                matrix[index * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
                matrix[index * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
            }
            guard let solution = Self.solve(matrix) else { return nil }
            coefficients = solution
        }

        func apply(to point: CGPoint) -> CGPoint {
            let x = Double(point.x)
            let y = Double(point.y)
            let denominator = coefficients[6] * x + coefficients[7] * y + 1
            return CGPoint(
                x: (coefficients[0] * x + coefficients[1] * y + coefficients[2]) / denominator,
                y: (coefficients[3] * x + coefficients[4] * y + coefficients[5]) / denominator
            )
        }

        private static func solve(_ augmented: [[Double]]) -> [Double]? {
            var values = augmented
            for column in 0..<8 {
                guard let pivot = (column..<8).max(by: {
                    abs(values[$0][column]) < abs(values[$1][column])
                }), abs(values[pivot][column]) > 1e-10 else { return nil }
                values.swapAt(column, pivot)
                let divisor = values[column][column]
                for item in column...8 { values[column][item] /= divisor }
                for row in 0..<8 where row != column {
                    let factor = values[row][column]
                    for item in column...8 {
                        values[row][item] -= factor * values[column][item]
                    }
                }
            }
            return values.map { $0[8] }
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        hypot(Double(x - other.x), Double(y - other.y))
    }
}

private extension PhotoCalibrationAnalyzer.Quadrilateral {
    func contains(
        _ other: PhotoCalibrationAnalyzer.Quadrilateral,
        tolerance: Double
    ) -> Bool {
        let horizontal = points.map(\.x)
        let vertical = points.map(\.y)
        guard let minimumX = horizontal.min(),
              let maximumX = horizontal.max(),
              let minimumY = vertical.min(),
              let maximumY = vertical.max() else { return false }
        return other.points.allSatisfy {
            $0.x >= minimumX - tolerance
                && $0.x <= maximumX + tolerance
                && $0.y >= minimumY - tolerance
                && $0.y <= maximumY + tolerance
        }
    }
}
