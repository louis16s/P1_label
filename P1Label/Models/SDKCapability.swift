import Foundation

enum SDKSupportLevel: String, CaseIterable {
    case supported
    case nativeAlternative
    case notApplicable
    case intentionallyUnavailable

    var title: String {
        switch self {
        case .supported: "已支持"
        case .nativeAlternative: "原生替代"
        case .notApplicable: "不适用于 macOS"
        case .intentionallyUnavailable: "未开放"
        }
    }
}

struct SDKCapability: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let level: SDKSupportLevel

    static let all: [SDKCapability] = [
        .init(name: "搜索、连接与断开", detail: "支持 USB 自动检测和蓝牙扫描、连接、断开。", level: .supported),
        .init(name: "打印机状态", detail: "支持就绪、缺纸、开盖、过热、电压、打印头、碳带与标签卷状态。", level: .supported),
        .init(name: "纸张与打印参数", detail: "支持连续纸、间隙纸、黑标纸、间隙长度、浓度、速度、份数、反色和双向偏移。", level: .supported),
        .init(name: "页面与预览", detail: "支持标签尺寸、适应画布和最终栅格预览；元素可独立旋转。", level: .supported),
        .init(name: "文字", detail: "支持系统字体、自定义字体、粗体、斜体、下划线、删除线、对齐与旋转。", level: .supported),
        .init(name: "条码与二维码", detail: "支持 Code 128 条码和二维码；更多一维码制式尚未加入编辑器。", level: .supported),
        .init(name: "图片与黑白转换", detail: "支持本地图片、彩色/灰度/打印预览、阈值与多种抖动算法。", level: .supported),
        .init(name: "图形", detail: "支持直线、矩形和椭圆；圆形可通过等宽等高的椭圆实现。", level: .supported),
        .init(name: "批量打印", detail: "支持连续序号、CSV 字段替换和多份打印。", level: .supported),
        .init(name: "SDK 的 UIImage、UIView 绘制", detail: "属于 iOS/UIKit 接口；macOS 使用 AppKit/Core Graphics 渲染，输出效果等价。", level: .nativeAlternative),
        .init(name: "SDK 内置设备列表界面", detail: "属于 iOS 界面；已由独立的原生“打印机”窗口替代。", level: .nativeAlternative),
        .init(name: "设备详细信息", detail: "当前可显示连接名称、接口和状态；SDK 未提供 P1 公开命令以读取固件、硬件版本及制造信息。", level: .intentionallyUnavailable),
        .init(name: "更多一维码制式", detail: "当前原生渲染器只提供 Code 128；UPC、EAN、Code 39 等制式需加入可靠编码器后再开放。", level: .intentionallyUnavailable),
        .init(name: "iOS 后台打印模式", detail: "仅适用于 iOS 应用生命周期，macOS 不需要该接口。", level: .notApplicable),
        .init(name: "打印机固件升级", detail: "误用错误固件可能损坏设备；在没有官方 P1 固件校验规范前不开放。", level: .intentionallyUnavailable)
    ]
}
