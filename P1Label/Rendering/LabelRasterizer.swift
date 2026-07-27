import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum LabelRasterizer {
    private static let dotsPerMillimeter = 8.0

    static func raster(
        document: LabelDocument,
        horizontalOffsetMM: Double,
        verticalOffsetMM: Double
    ) throws -> P1Raster {
        let width = P1Protocol.printWidthBytes * 8
        let height = max(1, Int((document.paper.heightMM * dotsPerMillimeter).rounded()))
        let printerWidthMM = Double(width) / dotsPerMillimeter
        let paperRightAlignmentMM = max(0, printerWidthMM - document.paper.widthMM)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderError.cannotCreateCanvas
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        for layer in document.layers {
            draw(
                layer,
                in: context,
                offsetX: (paperRightAlignmentMM + horizontalOffsetMM) * dotsPerMillimeter,
                offsetY: verticalOffsetMM * dotsPerMillimeter
            )
        }

        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw RenderError.cannotReadPixels
        }

        var result = P1Raster(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let luminance = (
                    Int(pixels[offset]) * 299
                    + Int(pixels[offset + 1]) * 587
                    + Int(pixels[offset + 2]) * 114
                ) / 1000
                result[x, y] = pixels[offset + 3] > 16 && luminance < 160
            }
        }
        return result
    }

    private static func draw(_ layer: LabelLayer, in context: CGContext, offsetX: Double, offsetY: Double) {
        let scale = dotsPerMillimeter
        let rect = CGRect(
            x: (layer.x * scale) + offsetX,
            y: (layer.y * scale) + offsetY,
            width: layer.width * scale,
            height: layer.height * scale
        )

        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: layer.rotation * .pi / 180)
        context.translateBy(x: -rect.midX, y: -rect.midY)

        switch layer.kind {
        case .text:
            let size = max(6, layer.fontSizeMM * scale)
            var font = NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: size),
                toFamily: layer.fontName
            )
            if layer.isBold {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if layer.isItalic {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            let value = layer.text.isEmpty ? "文字" : layer.text
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = switch layer.textAlignment {
            case .leading: .left
            case .center: .center
            case .trailing: .right
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
            if layer.isUnderline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if layer.isStrikethrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            let attributed = NSAttributedString(
                string: value,
                attributes: attributes
            )
            attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        case .rectangle:
            NSColor.black.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()

        case .ellipse:
            NSColor.black.setStroke()
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = 2
            path.stroke()

        case .line:
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.move(to: rect.origin)
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.lineWidth = 2
            path.stroke()

        case .image:
            if let data = layer.imageData,
               let image = LabelImageProcessor.processedImage(
                    data: data,
                    width: Int(rect.width.rounded()),
                    height: Int(rect.height.rounded()),
                    threshold: layer.imageThreshold,
                    algorithm: layer.imageAlgorithm,
                    scaleMode: layer.imageScaleMode
               ) {
                // The document context uses a top-left origin. A CGImage drawn
                // directly into that flipped context is vertically mirrored,
                // unlike AppKit text and NSImage drawing. Flip only the local
                // image rectangle so the printed result matches the preview.
                context.saveGState()
                context.translateBy(x: rect.minX, y: rect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(origin: .zero, size: rect.size))
                context.restoreGState()
            }

        case .qrCode:
            if let image = qrImage(for: layer.text.isEmpty ? "P1 Label" : layer.text) {
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }

        case .barcode:
            if let image = barcodeImage(for: layer.text.isEmpty ? "P1-0001" : layer.text) {
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        context.restoreGState()
    }

    private static func qrImage(for value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ciContext.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: transformed.extent.size)
    }

    static func barcodeImage(for value: String) -> NSImage? {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(value.utf8)
        filter.quietSpace = 7
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ciContext.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: transformed.extent.size)
    }

    enum RenderError: LocalizedError {
        case cannotCreateCanvas
        case cannotReadPixels

        var errorDescription: String? {
            switch self {
            case .cannotCreateCanvas: "无法创建标签画布。"
            case .cannotReadPixels: "无法读取标签点阵。"
            }
        }
    }
}
