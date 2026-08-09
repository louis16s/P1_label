import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Keeps expensive editor previews out of SwiftUI body evaluation.
/// Selection changes can invalidate canvas rows, but unchanged artwork is
/// returned from this cache instead of being decoded and rasterized again.
@MainActor
final class LabelPreviewCache {
    static let shared = LabelPreviewCache()

    private let images = NSCache<NSString, NSImage>()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {
        images.countLimit = 128
        images.totalCostLimit = 64 * 1_024 * 1_024
    }

    func removeAll() {
        images.removeAllObjects()
    }

    func imagePreview(for layer: LabelLayer, scale: Double) -> NSImage? {
        guard let data = layer.imageData,
              layer.width.isFinite,
              layer.height.isFinite,
              scale.isFinite else { return nil }
        let width = Int(min(4_096, max(1, (layer.width * scale).rounded())))
        let height = Int(min(4_096, max(1, (layer.height * scale).rounded())))
        let key = NSString(
            string: [
                "image",
                layer.id.uuidString,
                String(data.count),
                String(width),
                String(height),
                layer.imagePreviewMode.rawValue,
                layer.imageAlgorithm.rawValue,
                layer.imageScaleMode.rawValue,
                String(layer.imageThreshold)
            ].joined(separator: ":")
        )
        if let cached = images.object(forKey: key) { return cached }
        guard let cgImage = LabelImageProcessor.previewImage(
            data: data,
            width: width,
            height: height,
            previewMode: layer.imagePreviewMode,
            threshold: layer.imageThreshold,
            algorithm: layer.imageAlgorithm,
            scaleMode: layer.imageScaleMode
        ) else { return nil }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        images.setObject(image, forKey: key, cost: width * height * 4)
        return image
    }

    func qrCode(_ value: String) -> NSImage? {
        let content = value.isEmpty ? "P1 Label" : value
        let key = NSString(string: "qr:\(content)")
        if let cached = images.object(forKey: key) { return cached }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        let image = NSImage(cgImage: cgImage, size: scaled.extent.size)
        images.setObject(image, forKey: key, cost: cgImage.width * cgImage.height * 4)
        return image
    }

    func barcode(_ value: String) -> NSImage? {
        let content = value.isEmpty ? "P1-0001" : value
        let key = NSString(string: "barcode:\(content)")
        if let cached = images.object(forKey: key) { return cached }
        guard let image = LabelRasterizer.barcodeImage(for: content) else { return nil }
        images.setObject(
            image,
            forKey: key,
            cost: max(1, Int(image.size.width * image.size.height * 4))
        )
        return image
    }
}
