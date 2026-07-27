import Foundation
import P1USBBridge

actor P1USBTransport: PrinterTransport {
    let transportName = "USB"
    private var connection: OpaquePointer?

    func connect() throws {
        if connection != nil { return }
        var result = P1USBResultOK
        guard let opened = p1_usb_open(&result) else {
            throw P1USBError(result: result)
        }
        connection = opened
    }

    func send(_ data: Data) async throws {
        try connect()
        guard let connection else { throw PrinterTransportError.noDevice }
        defer { closeConnection() }
        let result: P1USBResult = data.withUnsafeBytes { buffer in
            p1_usb_send(connection, buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
        }
        guard result == P1USBResultOK else { throw P1USBError(result: result) }
    }

    func disconnect() async {
        closeConnection()
    }

    func readPortStatus() throws -> P1PrinterPortStatus {
        try connect()
        guard let connection else { throw PrinterTransportError.noDevice }
        defer { closeConnection() }
        var byte: UInt8 = 0
        let result = p1_usb_get_port_status(connection, &byte)
        guard result == P1USBResultOK else { throw P1USBError(result: result) }
        return P1PrinterPortStatus(rawValue: byte)
    }

    private func closeConnection() {
        guard let connection else { return }
        p1_usb_close(connection)
        self.connection = nil
    }
}

private struct P1USBError: LocalizedError {
    let result: P1USBResult

    var errorDescription: String? {
        switch result {
        case P1USBResultNotFound: "未找到德佟 P1 USB 设备。"
        case P1USBResultInterfaceNotFound: "找到 P1，但没有发现可写入的 USB 打印接口。"
        case P1USBResultClaimFailed: "P1 打印接口正被其他程序占用。"
        case P1USBResultWriteFailed: "向 P1 发送打印数据失败。"
        case P1USBResultInvalidArgument: "打印数据无效。"
        case P1USBResultReadFailed: "打印机没有返回 USB 端口状态。"
        default: "无法打开 P1 USB 设备。"
        }
    }
}

struct P1PrinterPortStatus: Equatable {
    let rawValue: UInt8
    var isPaperEmpty: Bool { rawValue & 0x20 != 0 }
    var isSelected: Bool { rawValue & 0x10 != 0 }
    var hasError: Bool { rawValue & 0x08 == 0 }

    var displayName: String {
        if isPaperEmpty { return "缺纸" }
        if hasError { return "设备错误（请检查纸仓盖和卡纸）" }
        if !isSelected { return "未联机" }
        return "就绪"
    }
}
