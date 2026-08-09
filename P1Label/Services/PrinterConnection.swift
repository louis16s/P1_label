import Foundation

enum PrinterConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting(String)
    case connected(String)
    case failed(String)
}

enum PrinterTransportError: LocalizedError {
    case busy
    case bluetoothNotReady
    case noWritableCharacteristic
    case disconnected
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .busy: "打印机正在接收上一项任务。"
        case .bluetoothNotReady: "蓝牙打印通道尚未准备好。"
        case .noWritableCharacteristic: "已连接设备，但没有发现可写入的蓝牙打印通道。"
        case .disconnected: "蓝牙打印机已断开连接。"
        case .timedOut(let operation): "\(operation)超时，请检查打印机后重试。"
        }
    }
}
