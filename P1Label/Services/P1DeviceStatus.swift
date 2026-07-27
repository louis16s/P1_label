import Foundation

enum P1DeviceStatusSeverity: Equatable {
    case ready
    case warning
    case error
    case unknown
}

struct P1DeviceStatus: Equatable, Sendable {
    let code: UInt8?
    let title: String
    let detail: String
    let severity: P1DeviceStatusSeverity

    var isReady: Bool { severity == .ready }

    static let ready = P1DeviceStatus(
        code: 0,
        title: "打印机就绪",
        detail: "纸张、打印头和上盖状态正常。",
        severity: .ready
    )

    static let unknown = P1DeviceStatus(
        code: nil,
        title: "状态未知",
        detail: "打印机已连接，但尚未返回设备状态。",
        severity: .unknown
    )

    static func sdk(code: UInt8) -> P1DeviceStatus {
        switch code {
        case 0x00:
            return .ready
        case 0x20:
            return error(code, "无法打印", "当前环境不满足打印条件，请检查纸张、上盖和打印头。")
        case 0x30:
            return error(code, "电压过低", "请使用稳定电源，并等待电压恢复后再打印。")
        case 0x31:
            return error(code, "电压过高", "请断开异常电源，使用打印机要求的电源后重试。")
        case 0x32:
            return error(code, "未检测到打印头", "请关闭打印机并检查打印头连接。")
        case 0x33:
            return warning(code, "打印头过热", "请暂停打印，等待打印头冷却。")
        case 0x34:
            return error(code, "纸仓盖已打开", "请合上纸仓盖并确认已扣紧。")
        case 0x35:
            return error(code, "打印机缺纸", "请装入标签纸，并让纸张越过传感器。")
        case 0x36:
            return error(code, "打印头未锁紧", "请重新合上纸仓盖并锁紧打印头。")
        case 0x37:
            return error(code, "未安装碳带", "当前耗材模式需要碳带，请检查耗材。")
        case 0x38:
            return error(code, "碳带不匹配", "请安装与当前任务匹配的碳带。")
        case 0x39:
            return warning(code, "环境温度过低", "请将打印机移至适宜温度环境，稍候再试。")
        case 0x40:
            return error(code, "碳带已用尽", "请更换碳带。")
        case 0x41:
            return error(code, "彩色碳带已用尽", "请更换彩色碳带。")
        case 0x42:
            return error(code, "未安装标签卷", "请安装标签卷，并让纸张越过传感器。")
        case 0x43:
            return error(code, "标签卷不匹配", "请检查标签规格或重新校准纸张。")
        case 0x44:
            return error(code, "标签卷已用尽", "请更换标签卷。")
        default:
            return P1DeviceStatus(
                code: code,
                title: "打印机状态异常",
                detail: "打印机返回未识别状态 \(code)，请检查设备。",
                severity: .error
            )
        }
    }

    static func usb(_ status: P1PrinterPortStatus) -> P1DeviceStatus {
        if status.isPaperEmpty {
            return error(0x35, "打印机缺纸", "请装入标签纸，并让纸张越过传感器。")
        }
        if status.hasError {
            return error(nil, "设备错误", "USB 状态无法区分上盖、过热或卡纸，请检查打印机。")
        }
        if !status.isSelected {
            return P1DeviceStatus(
                code: nil,
                title: "打印机未联机",
                detail: "请检查打印机电源和 USB 连接。",
                severity: .warning
            )
        }
        return .ready
    }

    private static func error(_ code: UInt8?, _ title: String, _ detail: String) -> P1DeviceStatus {
        P1DeviceStatus(code: code, title: title, detail: detail, severity: .error)
    }

    private static func warning(_ code: UInt8?, _ title: String, _ detail: String) -> P1DeviceStatus {
        P1DeviceStatus(code: code, title: title, detail: detail, severity: .warning)
    }
}
