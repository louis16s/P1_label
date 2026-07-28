import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum LabelRasterizer {
    static func raster(
        document: LabelDocument,
        horizontalOffsetMM: Double,
        verticalOffsetMM: Double
    ) throws -> P1Raster {
        try validate(document: document)
        guard horizontalOffsetMM.isFinite,
              verticalOffsetMM.isFinite,
              abs(horizontalOffsetMM) <= 10,
              abs(verticalOffsetMM) <= 10 else {
            throw RenderError.invalidOffset
        }
        let width = P1PrintGeometry.maximumWidthDots
        let height = P1PrintGeometry.dots(forMillimeters: document.paper.heightMM)
        let paperWidth = P1PrintGeometry.dots(forMillimeters: document.paper.widthMM)
        let paperRightAlignment = max(0, width - paperWidth)
        let horizontalOffset = P1PrintGeometry.dots(forMillimeters: horizontalOffsetMM)
        let verticalOffset = P1PrintGeometry.dots(forMillimeters: verticalOffsetMM)
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

        for layer in document.layers where !layer.isHidden {
            try Task.checkCancellation()
            draw(
                layer,
                in: context,
                offsetX: Double(paperRightAlignment + horizontalOffset),
                offsetY: Double(verticalOffset)
            )
        }

        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw RenderError.cannotReadPixels
        }

        var result = P1Raster(width: width, height: height)
        for y in 0..<height {
            if y.isMultiple(of: 32) {
                try Task.checkCancellation()
            }
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
        let scale = P1PrintGeometry.dotsPerMillimeter
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
            let font = LabelTextMetrics.font(
                family: layer.fontName,
                pointSize: size,
                isBold: layer.isBold,
                isItalic: layer.isItalic
            )
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
        case invalidPaperWidth
        case invalidPaperHeight
        case invalidLayerGeometry
        case invalidOffset

        var errorDescription: String? {
            switch self {
            case .cannotCreateCanvas: "无法创建标签画布。"
            case .cannotReadPixels: "无法读取标签点阵。"
            case .invalidPaperWidth: "标签宽度必须大于 0 且不能超过 P1 打印头的 48 mm。"
            case .invalidPaperHeight: "标签高度超出 P1 单页协议支持范围。"
            case .invalidLayerGeometry: "标签包含无效的元素尺寸或坐标，请检查元素位置和大小。"
            case .invalidOffset: "打印偏移必须位于 -10 mm 到 10 mm 之间。"
            }
        }
    }

    private static func validate(document: LabelDocument) throws {
        let paper = document.paper
        guard paper.widthMM.isFinite,
              paper.widthMM > 0,
              (1...P1PrintGeometry.maximumWidthDots).contains(
                P1PrintGeometry.dots(forMillimeters: paper.widthMM)
              ) else {
            throw RenderError.invalidPaperWidth
        }
        let height = P1PrintGeometry.dots(forMillimeters: paper.heightMM)
        guard paper.heightMM.isFinite,
              paper.heightMM > 0,
              height > 0,
              height <= P1PrintGeometry.maximumPageHeightDots else {
            throw RenderError.invalidPaperHeight
        }
        let maximumDimensionMM = Double(P1PrintGeometry.maximumPageHeightDots)
            / P1PrintGeometry.dotsPerMillimeter
        guard document.layers.allSatisfy({
            $0.x.isFinite
                && $0.y.isFinite
                && $0.width.isFinite
                && $0.height.isFinite
                && $0.rotation.isFinite
                && $0.fontSizeMM.isFinite
                && $0.width > 0
                && $0.height > 0
                && $0.fontSizeMM > 0
                && abs($0.x) <= maximumDimensionMM
                && abs($0.y) <= maximumDimensionMM
                && $0.width <= maximumDimensionMM
                && $0.height <= maximumDimensionMM
                && $0.fontSizeMM <= 100
                && abs($0.rotation) <= 360_000
        }) else {
            throw RenderError.invalidLayerGeometry
        }
    }
}
