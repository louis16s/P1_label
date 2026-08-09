import Foundation

struct DiagnosticSnapshot: Sendable {
    let generatedAt: Date
    let appVersion: String
    let appBuild: String
    let operatingSystem: String
    let architecture: String
    let connectionKind: String
    let usbDeviceCount: Int
    let bluetoothState: String
    let deviceStatus: P1DeviceStatus?
    let recentPrintStates: [PrintHistoryEntry.Status]
}

enum DiagnosticReportService {
    nonisolated static func report(for snapshot: DiagnosticSnapshot) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "P1 Label 脱敏诊断报告",
            "生成时间：\(formatter.string(from: snapshot.generatedAt))",
            "软件版本：\(snapshot.appVersion) (\(snapshot.appBuild))",
            "系统：\(snapshot.operatingSystem)",
            "架构：\(snapshot.architecture)",
            "连接类型：\(snapshot.connectionKind)",
            "USB 目标设备数量：\(snapshot.usbDeviceCount)",
            "蓝牙状态：\(snapshot.bluetoothState)"
        ]
        if let status = snapshot.deviceStatus {
            lines.append("打印机状态：\(status.title)")
            let detail = PrinterStatusText.normalize(status.detail)
            lines.append("状态说明：\(detail)")
            if let code = status.code {
                lines.append("SDK 状态码：\(code)")
            }
        } else {
            lines.append("打印机状态：未读取")
        }
        let stateCounts = Dictionary(grouping: snapshot.recentPrintStates, by: { $0 })
        lines.append("最近任务数量：\(snapshot.recentPrintStates.count)")
        for state in [PrintHistoryEntry.Status.succeeded, .failed, .cancelled, .sending] {
            lines.append("- \(state.displayName)：\(stateCounts[state]?.count ?? 0)")
        }
        lines.append("")
        lines.append("隐私说明：报告不包含标签内容、文档名称、文件路径、图片、打印数据、蓝牙标识或 USB 位置编号")
        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated static func write(_ snapshot: DiagnosticSnapshot, to url: URL) async throws {
        let data = Data(report(for: snapshot).utf8)
        try await Task.detached(priority: .utility) {
            try data.write(to: url, options: .atomic)
        }.value
    }
}
