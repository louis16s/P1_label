import Foundation

struct LabelDocument: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var paper: PaperSize
    var layers: [LabelLayer]

    static let blank = LabelDocument(
        name: "未命名标签",
        paper: .init(widthMM: 40, heightMM: 30),
        layers: []
    )

    static let example = LabelDocument(
        name: "未命名标签",
        paper: .init(widthMM: 40, heightMM: 30),
        layers: [
            .text("德佟 P1", x: 4, y: 4, fontSizeMM: 5),
            .text("macOS 原生标签客户端", x: 4, y: 12, fontSizeMM: 2.4),
            .text("USB / Bluetooth", x: 4, y: 18, fontSizeMM: 2.4)
        ]
    )
}

struct PaperSize: Codable, Hashable, Sendable {
    var widthMM: Double
    var heightMM: Double

    var pixelWidth: Int {
        min(
            P1PrintGeometry.maximumWidthDots,
            max(1, P1PrintGeometry.dots(forMillimeters: widthMM))
        )
    }
    var pixelHeight: Int {
        min(
            P1PrintGeometry.maximumPageHeightDots,
            max(1, P1PrintGeometry.dots(forMillimeters: heightMM))
        )
    }
    var displayName: String {
        let width = widthMM.isFinite ? widthMM.formatted(.number.precision(.fractionLength(0...1))) : "?"
        let height = heightMM.isFinite ? heightMM.formatted(.number.precision(.fractionLength(0...1))) : "?"
        return "\(width) × \(height) mm"
    }
}

enum LabelTextAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

enum LabelImageScaleMode: String, Codable, CaseIterable, Sendable {
    case fit
    case fill

    var displayName: String {
        switch self {
        case .fit: "完整适应"
        case .fill: "填充裁剪"
        }
    }
}

enum LabelImageAlgorithm: String, Codable, CaseIterable, Sendable {
    case threshold
    case otsu
    case floydSteinberg
    case atkinson
    case orderedBayer

    var displayName: String {
        switch self {
        case .threshold: "硬阈值"
        case .otsu: "自动阈值（Otsu）"
        case .floydSteinberg: "Floyd–Steinberg"
        case .atkinson: "Atkinson"
        case .orderedBayer: "Bayer 网点"
        }
    }

    var description: String {
        switch self {
        case .threshold: "边缘最锐利，适合文字、图标和二维码"
        case .otsu: "自动分析明暗分布，适合扫描件和背景不均的图片"
        case .floydSteinberg: "层次丰富，适合照片和渐变"
        case .atkinson: "颗粒更轻，适合人像和浅色图片"
        case .orderedBayer: "网点规则，适合稳定快速的批量打印"
        }
    }
}

enum LabelImagePreviewMode: String, Codable, CaseIterable, Sendable {
    case color
    case grayscale
    case printResult

    var displayName: String {
        switch self {
        case .color: "彩色"
        case .grayscale: "灰度"
        case .printResult: "打印效果"
        }
    }
}

struct LabelLayer: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case text, image, qrCode, barcode, rectangle, ellipse, line
    }

    var id = UUID()
    var kind: Kind
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double = 0
    var isHidden = false
    var isLocked = false
    var text = ""
    var fontSizeMM: Double = 3
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var textAlignment: LabelTextAlignment = .leading
    var fontName = ".AppleSystemUIFont"
    var imageData: Data?
    var imageThreshold = 0.62
    var imageAlgorithm: LabelImageAlgorithm = .floydSteinberg
    var imagePreviewMode: LabelImagePreviewMode = .color
    var imageScaleMode: LabelImageScaleMode = .fit

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, x, y, width, height, rotation, isHidden, isLocked
        case text, fontSizeMM, isBold, isItalic, isUnderline, isStrikethrough
        case textAlignment, fontName, imageData, imageThreshold, imageDither
        case imageAlgorithm, imagePreviewMode, imageScaleMode
    }

    init(
        id: UUID = UUID(),
        kind: Kind,
        name: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        rotation: Double = 0,
        isHidden: Bool = false,
        isLocked: Bool = false,
        text: String = "",
        fontSizeMM: Double = 3,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        isStrikethrough: Bool = false,
        textAlignment: LabelTextAlignment = .leading,
        fontName: String = ".AppleSystemUIFont",
        imageData: Data? = nil,
        imageThreshold: Double = 0.62,
        imageAlgorithm: LabelImageAlgorithm = .floydSteinberg,
        imagePreviewMode: LabelImagePreviewMode = .color,
        imageScaleMode: LabelImageScaleMode = .fit
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.isHidden = isHidden
        self.isLocked = isLocked
        self.text = text
        self.fontSizeMM = fontSizeMM
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isStrikethrough = isStrikethrough
        self.textAlignment = textAlignment
        self.fontName = fontName
        self.imageData = imageData
        self.imageThreshold = imageThreshold
        self.imageAlgorithm = imageAlgorithm
        self.imagePreviewMode = imagePreviewMode
        self.imageScaleMode = imageScaleMode
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try values.decode(Kind.self, forKey: .kind)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "对象"
        x = try values.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try values.decodeIfPresent(Double.self, forKey: .y) ?? 0
        width = try values.decodeIfPresent(Double.self, forKey: .width) ?? 10
        height = try values.decodeIfPresent(Double.self, forKey: .height) ?? 5
        rotation = try values.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isHidden = try values.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        fontSizeMM = try values.decodeIfPresent(Double.self, forKey: .fontSizeMM) ?? 3
        isBold = try values.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try values.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        isUnderline = try values.decodeIfPresent(Bool.self, forKey: .isUnderline) ?? false
        isStrikethrough = try values.decodeIfPresent(Bool.self, forKey: .isStrikethrough) ?? false
        textAlignment = try values.decodeIfPresent(LabelTextAlignment.self, forKey: .textAlignment) ?? .leading
        fontName = try values.decodeIfPresent(String.self, forKey: .fontName) ?? ".AppleSystemUIFont"
        imageData = try values.decodeIfPresent(Data.self, forKey: .imageData)
        imageThreshold = try values.decodeIfPresent(Double.self, forKey: .imageThreshold) ?? 0.62
        if let savedAlgorithm = try values.decodeIfPresent(
            LabelImageAlgorithm.self,
            forKey: .imageAlgorithm
        ) {
            imageAlgorithm = savedAlgorithm
        } else {
            let legacyDither = try values.decodeIfPresent(Bool.self, forKey: .imageDither) ?? true
            imageAlgorithm = legacyDither ? .floydSteinberg : .threshold
        }
        imagePreviewMode = try values.decodeIfPresent(
            LabelImagePreviewMode.self,
            forKey: .imagePreviewMode
        ) ?? .printResult
        imageScaleMode = try values.decodeIfPresent(LabelImageScaleMode.self, forKey: .imageScaleMode) ?? .fit
        if kind == .text, abs(height - fontSizeMM) < 0.051 {
            height = LabelTextMetrics.automaticHeightMM(
                family: fontName,
                fontSizeMM: fontSizeMM,
                isBold: isBold,
                isItalic: isItalic
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(name, forKey: .name)
        try values.encode(x, forKey: .x)
        try values.encode(y, forKey: .y)
        try values.encode(width, forKey: .width)
        try values.encode(height, forKey: .height)
        try values.encode(rotation, forKey: .rotation)
        try values.encode(isHidden, forKey: .isHidden)
        try values.encode(isLocked, forKey: .isLocked)
        try values.encode(text, forKey: .text)
        try values.encode(fontSizeMM, forKey: .fontSizeMM)
        try values.encode(isBold, forKey: .isBold)
        try values.encode(isItalic, forKey: .isItalic)
        try values.encode(isUnderline, forKey: .isUnderline)
        try values.encode(isStrikethrough, forKey: .isStrikethrough)
        try values.encode(textAlignment, forKey: .textAlignment)
        try values.encode(fontName, forKey: .fontName)
        try values.encodeIfPresent(imageData, forKey: .imageData)
        try values.encode(imageThreshold, forKey: .imageThreshold)
        try values.encode(imageAlgorithm, forKey: .imageAlgorithm)
        try values.encode(imagePreviewMode, forKey: .imagePreviewMode)
        try values.encode(imageScaleMode, forKey: .imageScaleMode)
    }

    static func text(_ value: String, x: Double, y: Double, fontSizeMM: Double) -> LabelLayer {
        LabelLayer(
            kind: .text,
            name: value,
            x: x,
            y: y,
            width: 32,
            height: LabelTextMetrics.automaticHeightMM(
                family: ".AppleSystemUIFont",
                fontSizeMM: fontSizeMM
            ),
            text: value,
            fontSizeMM: fontSizeMM
        )
    }

    static func shape(_ kind: Kind, x: Double, y: Double) -> LabelLayer {
        let title: String
        switch kind {
        case .rectangle: title = "矩形"
        case .ellipse: title = "圆形"
        case .line: title = "直线"
        case .qrCode: title = "二维码"
        case .barcode: title = "Code 128 条码"
        case .image: title = "图片"
        case .text: title = "文字"
        }
        var layer = LabelLayer(kind: kind, name: title, x: x, y: y, width: 16, height: 10)
        if kind == .qrCode {
            layer.width = 16
            layer.height = 16
            layer.text = "https://example.com"
        } else if kind == .barcode {
            layer.width = 28
            layer.height = 10
            layer.text = "P1-0001"
        }
        return layer
    }

    static func image(
        _ data: Data,
        name: String,
        x: Double,
        y: Double,
        aspectRatio: Double? = nil
    ) -> LabelLayer {
        let ratio = max(0.05, aspectRatio ?? (4.0 / 3.0))
        var width = 24.0
        var height = width / ratio
        if height > 18 {
            height = 18
            width = height * ratio
        }
        return LabelLayer(
            kind: .image,
            name: name,
            x: x,
            y: y,
            width: width,
            height: height,
            imageData: data
        )
    }
}
