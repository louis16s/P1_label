import AppKit
import Foundation
import ImageIO

enum LabelImageProcessor {
    static func sourceAspectRatio(data: Data) -> Double? {
        guard let image = decodedImage(data: data), image.height > 0 else { return nil }
        return Double(image.width) / Double(image.height)
    }

    static func previewImage(
        data: Data,
        width: Int,
        height: Int,
        previewMode: LabelImagePreviewMode,
        threshold: Double,
        algorithm: LabelImageAlgorithm,
        scaleMode: LabelImageScaleMode
    ) -> CGImage? {
        guard let rendered = renderedContext(
            data: data,
            width: width,
            height: height,
            scaleMode: scaleMode
        ) else { return nil }
        switch previewMode {
        case .color:
            break
        case .grayscale:
            writeGrayscale(pixels: rendered.pixels, width: rendered.width, height: rendered.height)
        case .printResult:
            writeMonochrome(
                pixels: rendered.pixels,
                width: rendered.width,
                height: rendered.height,
                threshold: threshold,
                algorithm: algorithm
            )
        }
        return rendered.context.makeImage()
    }

    static func processedImage(
        data: Data,
        width: Int,
        height: Int,
        threshold: Double,
        algorithm: LabelImageAlgorithm,
        scaleMode: LabelImageScaleMode
    ) -> CGImage? {
        guard let rendered = renderedContext(
            data: data,
            width: width,
            height: height,
            scaleMode: scaleMode
        ) else { return nil }
        writeMonochrome(
            pixels: rendered.pixels,
            width: rendered.width,
            height: rendered.height,
            threshold: threshold,
            algorithm: algorithm
        )
        return rendered.context.makeImage()
    }

    private static func decodedImage(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4_096,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func renderedContext(
        data: Data,
        width: Int,
        height: Int,
        scaleMode: LabelImageScaleMode
    ) -> (context: CGContext, pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int)? {
        guard let source = decodedImage(data: data) else { return nil }
        let targetWidth = max(1, width)
        let targetHeight = max(1, height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        context.interpolationQuality = .high
        let sourceRatio = Double(source.width) / Double(source.height)
        let targetRatio = Double(targetWidth) / Double(targetHeight)
        let drawRect: CGRect
        if (scaleMode == .fit && sourceRatio > targetRatio)
            || (scaleMode == .fill && sourceRatio < targetRatio) {
            let drawHeight = Double(targetWidth) / sourceRatio
            drawRect = CGRect(
                x: 0,
                y: (Double(targetHeight) - drawHeight) / 2,
                width: Double(targetWidth),
                height: drawHeight
            )
        } else {
            let drawWidth = Double(targetHeight) * sourceRatio
            drawRect = CGRect(
                x: (Double(targetWidth) - drawWidth) / 2,
                y: 0,
                width: drawWidth,
                height: Double(targetHeight)
            )
        }
        context.draw(source, in: drawRect)
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return (context, pixels, targetWidth, targetHeight)
    }

    private static func luminanceValues(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int
    ) -> [Double] {
        var values = [Double](repeating: 1, count: width * height)
        for index in values.indices {
            let offset = index * 4
            values[index] = (
                Double(pixels[offset]) * 0.299
                + Double(pixels[offset + 1]) * 0.587
                + Double(pixels[offset + 2]) * 0.114
            ) / 255
        }
        return values
    }

    private static func writeGrayscale(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int
    ) {
        let luminance = luminanceValues(pixels: pixels, width: width, height: height)
        for index in luminance.indices {
            let value = UInt8(clamping: Int((luminance[index] * 255).rounded()))
            setPixel(pixels, index: index, value: value)
        }
    }

    private static func writeMonochrome(
        pixels: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        threshold: Double,
        algorithm: LabelImageAlgorithm
    ) {
        var luminance = luminanceValues(pixels: pixels, width: width, height: height)
        let cutoff = algorithm == .otsu
            ? otsuThreshold(luminance)
            : min(1, max(0, threshold))
        let bayer4 = [
            0, 8, 2, 10,
            12, 4, 14, 6,
            3, 11, 1, 9,
            15, 7, 13, 5
        ]

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let oldValue = luminance[index]
                let localCutoff: Double
                if algorithm == .orderedBayer {
                    let matrixValue = Double(bayer4[(y % 4) * 4 + (x % 4)]) / 15
                    localCutoff = min(1, max(0, cutoff + (matrixValue - 0.5) * 0.45))
                } else {
                    localCutoff = cutoff
                }
                let newValue = oldValue < localCutoff ? 0.0 : 1.0
                luminance[index] = newValue
                let error = oldValue - newValue
                switch algorithm {
                case .threshold, .otsu, .orderedBayer:
                    break
                case .floydSteinberg:
                    distribute(error * 7 / 16, x: x + 1, y: y, values: &luminance,
                               width: width, height: height)
                    distribute(error * 3 / 16, x: x - 1, y: y + 1, values: &luminance,
                               width: width, height: height)
                    distribute(error * 5 / 16, x: x, y: y + 1, values: &luminance,
                               width: width, height: height)
                    distribute(error / 16, x: x + 1, y: y + 1, values: &luminance,
                               width: width, height: height)
                case .atkinson:
                    for point in [
                        (x + 1, y), (x + 2, y),
                        (x - 1, y + 1), (x, y + 1), (x + 1, y + 1),
                        (x, y + 2)
                    ] {
                        distribute(error / 8, x: point.0, y: point.1, values: &luminance,
                                   width: width, height: height)
                    }
                }
            }
        }

        for index in luminance.indices {
            setPixel(pixels, index: index, value: luminance[index] < 0.5 ? 0 : 255)
        }
    }

    private static func setPixel(
        _ pixels: UnsafeMutablePointer<UInt8>,
        index: Int,
        value: UInt8
    ) {
        let offset = index * 4
        pixels[offset] = value
        pixels[offset + 1] = value
        pixels[offset + 2] = value
        pixels[offset + 3] = 255
    }

    private static func otsuThreshold(_ luminance: [Double]) -> Double {
        guard !luminance.isEmpty else { return 0.5 }
        var histogram = [Int](repeating: 0, count: 256)
        for value in luminance {
            histogram[min(255, max(0, Int((value * 255).rounded())))] += 1
        }
        let total = Double(luminance.count)
        let totalWeighted = histogram.enumerated().reduce(0.0) {
            $0 + Double($1.offset * $1.element)
        }
        var backgroundWeight = 0.0
        var backgroundWeighted = 0.0
        var bestVariance = -1.0
        var bestLevel = 127

        for level in 0..<256 {
            backgroundWeight += Double(histogram[level])
            guard backgroundWeight > 0 else { continue }
            let foregroundWeight = total - backgroundWeight
            guard foregroundWeight > 0 else { break }
            backgroundWeighted += Double(level * histogram[level])
            let backgroundMean = backgroundWeighted / backgroundWeight
            let foregroundMean = (totalWeighted - backgroundWeighted) / foregroundWeight
            let difference = backgroundMean - foregroundMean
            let variance = backgroundWeight * foregroundWeight * difference * difference
            if variance > bestVariance {
                bestVariance = variance
                bestLevel = level
            }
        }
        return Double(bestLevel) / 255
    }

    private static func distribute(
        _ error: Double,
        x: Int,
        y: Int,
        values: inout [Double],
        width: Int,
        height: Int
    ) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let index = y * width + x
        values[index] = min(1, max(0, values[index] + error))
    }
}
