import AppKit
import Foundation

enum P1ImageRasterizer {
    static func raster(fromDataURL value: String) throws -> P1Raster {
        guard let separator = value.firstIndex(of: ","),
              let data = Data(base64Encoded: String(value[value.index(after: separator)...])),
              let image = NSBitmapImageRep(data: data) else {
            throw RasterError.invalidImage
        }

        let sourceWidth = image.pixelsWide
        let sourceHeight = image.pixelsHigh
        guard sourceWidth > 0, sourceHeight > 0 else { throw RasterError.invalidImage }

        let targetWidth = P1Protocol.printWidthBytes * 8
        let targetHeight = sourceWidth > targetWidth
            ? max(1, Int((Double(sourceHeight) * Double(targetWidth) / Double(sourceWidth)).rounded()))
            : sourceHeight
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = image.cgImage else { throw RasterError.renderFailed }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        let drawWidth = min(targetWidth, sourceWidth)
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: drawWidth, height: targetHeight))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { throw RasterError.renderFailed }

        var raster = P1Raster(width: targetWidth, height: targetHeight)
        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let offset = (y * targetWidth + x) * 4
                let alpha = pixels[offset + 3]
                let luminance = (Int(pixels[offset]) * 299 + Int(pixels[offset + 1]) * 587 + Int(pixels[offset + 2]) * 114) / 1000
                raster[x, targetHeight - y - 1] = alpha > 16 && luminance < 128
            }
        }
        return raster
    }

    enum RasterError: LocalizedError {
        case invalidImage
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage: "网页编辑器没有提供有效的 PNG。"
            case .renderFailed: "无法将 PNG 转换为 P1 点阵。"
            }
        }
    }
}
