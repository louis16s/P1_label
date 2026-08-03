import Foundation
import P1USBBridge

actor P1USBTransport: PrinterTransport {
    let transportName = "USB"
    private var operationInProgress = false

    func connect() async throws {
        try beginOperation()
        defer { operationInProgress = false }
        try await Self.runDetached {
            try Self.withConnection { _ in () }
        }
    }

    func send(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        try beginOperation()
        defer { operationInProgress = false }
        try await Self.runDetached {
            try Self.withConnection { connection in
                let result: P1USBResult = data.withUnsafeBytes { buffer in
                    p1_usb_send(
                        connection,
                        buffer.bindMemory(to: UInt8.self).baseAddress,
                        buffer.count
                    )
                }
                guard result == P1USBResultOK else { throw P1USBError(result: result) }
            }
        }
    }

    func disconnect() async {}

    func readPortStatus() async throws -> P1PrinterPortStatus {
        try beginOperation()
        defer { operationInProgress = false }
        return try await Self.runDetached {
            try Self.withConnection { connection in
                var byte: UInt8 = 0
                let result = p1_usb_get_port_status(connection, &byte)
                guard result == P1USBResultOK else { throw P1USBError(result: result) }
                return P1PrinterPortStatus(rawValue: byte)
            }
        }
    }

    private func beginOperation() throws {
        guard !operationInProgress else { throw PrinterTransportError.busy }
        operationInProgress = true
    }

    nonisolated private static func withConnection<Value: Sendable>(
        operation: (OpaquePointer) throws -> Value
    ) throws -> Value {
        var result = P1USBResultOK
        guard let connection = p1_usb_open(&result) else {
            throw P1USBError(result: result)
        }
        defer { p1_usb_close(connection) }
        return try operation(connection)
    }

    nonisolated private static func runDetached<Value: Sendable>(
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
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

struct P1PrinterPortStatus: Equatable, Sendable {
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
