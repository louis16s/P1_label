import Foundation

enum DocumentTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank
    case address
    case price
    case asset

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: "空白标签"
        case .address: "地址标签"
        case .price: "价格标签"
        case .asset: "资产标签"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: "doc"
        case .address: "shippingbox"
        case .price: "tag"
        case .asset: "qrcode"
        }
    }

    func makeDocument() -> LabelDocument {
        switch self {
        case .blank:
            return LabelDocument(
                name: "未命名标签",
                paper: PaperSize(widthMM: 40, heightMM: 30),
                layers: []
            )
        case .address:
            var recipient = LabelLayer.text("收件人：姓名", x: 3, y: 3, fontSizeMM: 4)
            recipient.width = 34
            var phone = LabelLayer.text("电话：138 0000 0000", x: 3, y: 10, fontSizeMM: 2.6)
            phone.width = 34
            var address = LabelLayer.text("地址：省 / 市 / 区 / 街道门牌", x: 3, y: 16, fontSizeMM: 2.6)
            address.width = 34
            address.height = 10
            return LabelDocument(
                name: "地址标签",
                paper: PaperSize(widthMM: 40, heightMM: 30),
                layers: [recipient, phone, address]
            )
        case .price:
            var product = LabelLayer.text("商品名称", x: 3, y: 3, fontSizeMM: 3.5)
            product.width = 34
            var price = LabelLayer.text("¥ 99.00", x: 3, y: 9, fontSizeMM: 7)
            price.width = 34
            price.isBold = true
            var barcode = LabelLayer.shape(.barcode, x: 6, y: 20)
            barcode.width = 28
            barcode.height = 8
            return LabelDocument(
                name: "价格标签",
                paper: PaperSize(widthMM: 40, heightMM: 30),
                layers: [product, price, barcode]
            )
        case .asset:
            var title = LabelLayer.text("资产名称", x: 3, y: 2, fontSizeMM: 3.5)
            title.width = 34
            title.isBold = true
            var code = LabelLayer.shape(.qrCode, x: 3, y: 9)
            code.width = 18
            code.height = 18
            code.text = "P1-ASSET-0001"
            var number = LabelLayer.text("编号：0001", x: 23, y: 11, fontSizeMM: 2.4)
            number.width = 14
            var department = LabelLayer.text("部门：未分配", x: 23, y: 17, fontSizeMM: 2.4)
            department.width = 14
            department.height = 8
            return LabelDocument(
                name: "资产标签",
                paper: PaperSize(widthMM: 40, heightMM: 30),
                layers: [title, code, number, department]
            )
        }
    }
}

enum PendingDocumentAction: Sendable, Equatable {
    case newDocument(DocumentTemplate)
    case open(URL)
    case terminate

    var confirmationName: String {
        switch self {
        case .newDocument: "新建标签"
        case .open: "打开其他标签"
        case .terminate: "退出 P1 Label"
        }
    }
}

enum UnsavedChangesDecision {
    case save
    case discard
    case cancel
}
