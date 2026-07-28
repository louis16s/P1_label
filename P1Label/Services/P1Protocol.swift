import Foundation

enum P1PaperMode: Int, CaseIterable, Identifiable, Codable, Sendable {
    case continuous = 0
    case gap = 2
    case blackMark = 3
    case transparentBlackMark = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .continuous: "连续纸"
        case .gap: "间隙标签纸"
        case .blackMark: "黑标卡纸"
        case .transparentBlackMark: "透明黑标纸"
        }
    }
}

/// The direct USB command subset independently confirmed by kaori3.
enum P1Protocol {
    static let vendorID: UInt16 = 0x3533
    static let productID: UInt16 = 0x5A11
    static let printWidthBytes = 48 // 384 dots / 48 mm at 8 dots per mm

    static let pageStart = Data([0x1F, 0x20, 0x00, 0x88])
    static let pageEnd = Data([0x1F, 0x28, 0x00, 0x88])

    static func setPrintWidth(bytes: UInt8 = UInt8(printWidthBytes)) -> Data {
        Data([0x1F, 0x27, 0x01, bytes, 0x88])
    }

    /// Confirmed from DeTong's current LPAPI SDK package format.
    static func setGapType(_ mode: P1PaperMode) -> Data {
        let officialType = mode == .transparentBlackMark ? P1PaperMode.blackMark.rawValue : mode.rawValue
        return Data([0x1F, 0x42, 0x01, UInt8(officialType), 0x88])
    }

    static func setPageHeight(dots: Int) -> Data {
        variableLengthCommand(code: 0x26, value: dots)
    }

    static func setGapLength(millimeters: Int) -> Data {
        variableLengthCommand(code: 0x45, value: millimeters)
    }

    static func setDarkness(_ darkness: Int) -> Data {
        guard darkness > 0 else { return Data() }
        return Data([0x1F, 0x43, 0x01, UInt8(clamping: darkness - 1), 0x88])
    }

    static func setSpeed(_ speed: Int) -> Data {
        guard speed > 0 else { return Data() }
        return Data([0x1F, 0x44, 0x01, UInt8(clamping: speed - 1), 0x88])
    }

    static func printRow(_ row: Data) -> Data {
        precondition(row.count <= Int(UInt16.max) / 8)
        let bitCount = UInt16(row.count * 8)
        return Data([0x1F, 0x2A, UInt8(bitCount & 0x00FF), UInt8(bitCount >> 8)]) + row
    }

    static func printJob(
        raster: P1Raster,
        paperMode: P1PaperMode,
        gapLengthMM: Int,
        darkness: Int,
        speed: Int
    ) -> Data {
        precondition(raster.width == printWidthBytes * 8)
        var job = pageStart
            + setGapType(paperMode)
            + setDarkness(darkness)
            + setSpeed(speed)
            + setPrintWidth()
        for row in raster.packedRows() {
            job += printRow(row)
        }
        job += setPageHeight(dots: raster.height)
        if paperMode != .continuous, gapLengthMM > 0 {
            job += setGapLength(millimeters: gapLengthMM)
        }
        return job + pageEnd
    }

    private static func variableLengthCommand(code: UInt8, value: Int) -> Data {
        let safeValue = max(0, min(value, 0x3FFF))
        if safeValue < 0xC0 {
            return Data([0x1F, code, 0x01, UInt8(safeValue), 0x88])
        }
        return Data([
            0x1F, code, 0x02,
            0xC0 | UInt8((safeValue >> 8) & 0x3F),
            UInt8(safeValue & 0xFF),
            0x88
        ])
    }
}
