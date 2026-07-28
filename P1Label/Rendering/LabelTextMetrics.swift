import AppKit
import Foundation

enum LabelTextMetrics {
    private static let cache = FontMetricCache()

    static func font(
        family: String,
        pointSize: Double,
        isBold: Bool = false,
        isItalic: Bool = false
    ) -> NSFont {
        cache.withLock {
            makeFont(
                family: family,
                pointSize: pointSize,
                isBold: isBold,
                isItalic: isItalic
            )
        }
    }

    private static func makeFont(
        family: String,
        pointSize: Double,
        isBold: Bool,
        isItalic: Bool
    ) -> NSFont {
        let manager = NSFontManager.shared
        var font = manager.convert(
            NSFont.systemFont(ofSize: max(1, pointSize)),
            toFamily: family
        )
        if isBold {
            font = manager.convert(font, toHaveTrait: .boldFontMask)
        }
        if isItalic {
            font = manager.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    static func automaticHeightMM(
        family: String,
        fontSizeMM: Double,
        isBold: Bool = false,
        isItalic: Bool = false
    ) -> Double {
        let key = FontMetricKey(family: family, isBold: isBold, isItalic: isItalic)
        let lineHeightRatio = cache.lineHeightRatio(for: key) {
            let referenceSize = 100.0
            let font = makeFont(
                family: family,
                pointSize: referenceSize,
                isBold: isBold,
                isItalic: isItalic
            )
            return Double(font.ascender - font.descender + font.leading) / referenceSize
        }
        return max(1, (fontSizeMM * lineHeightRatio * 10).rounded() / 10)
    }

    static func isAutomaticHeight(
        _ height: Double,
        family: String,
        fontSizeMM: Double,
        isBold: Bool = false,
        isItalic: Bool = false
    ) -> Bool {
        abs(height - fontSizeMM) < 0.051
            || abs(height - automaticHeightMM(
                family: family,
                fontSizeMM: fontSizeMM,
                isBold: isBold,
                isItalic: isItalic
            )) < 0.051
    }
}

private struct FontMetricKey: Hashable {
    let family: String
    let isBold: Bool
    let isItalic: Bool
}

private final class FontMetricCache: @unchecked Sendable {
    private let lock = NSLock()
    private var lineHeightRatios: [FontMetricKey: Double] = [:]

    func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    func lineHeightRatio(
        for key: FontMetricKey,
        calculate: () -> Double
    ) -> Double {
        withLock {
            if let cached = lineHeightRatios[key] {
                return cached
            }
            let value = calculate()
            lineHeightRatios[key] = value
            return value
        }
    }
}
