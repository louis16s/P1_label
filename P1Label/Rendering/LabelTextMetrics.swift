import AppKit
import Foundation

enum LabelTextMetrics {
    static func font(
        family: String,
        pointSize: Double,
        isBold: Bool = false,
        isItalic: Bool = false
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
        let referenceSize = 100.0
        let font = font(
            family: family,
            pointSize: referenceSize,
            isBold: isBold,
            isItalic: isItalic
        )
        let lineHeightRatio = Double(font.ascender - font.descender + font.leading) / referenceSize
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
