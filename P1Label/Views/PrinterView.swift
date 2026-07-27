import SwiftUI

struct PrinterView: View {
    @Bindable var model: AppModel
    @ObservedObject private var bluetoothDiscovery: BluetoothDiscovery

    init(model: AppModel) {
        self.model = model
        _bluetoothDiscovery = ObservedObject(wrappedValue: model.bluetoothDiscovery)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: model.hasConnectedPrinter ? "printer.fill" : "printer")
                        .font(.system(size: 30))
                        .foregroundStyle(model.hasConnectedPrinter ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.hasConnectedPrinter ? model.activePrintConnectionName : "尚未连接")
                            .font(.headline)
                        Text(model.bluetoothDiscovery.isConnected
                             ? "蓝牙打印通道已就绪"
                             : model.printStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("设备状态") {
                if let status = displayedDeviceStatus {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: statusIcon(status))
                            .foregroundStyle(statusColor(status))
                            .font(.title3)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(status.title).font(.headline)
                            Text(status.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let code = status.code, code != 0 {
                                Text("SDK 状态码 \(code)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("连接打印机后可读取缺纸、开盖、过热等状态。")
                        .foregroundStyle(.secondary)
                }
                Button("读取打印机状态", systemImage: "waveform.path.ecg") {
                    model.refreshPrinterStatus()
                }
                .disabled(!model.hasConnectedPrinter)
            }
            Section("USB") {
                LabeledContent("目标设备", value: "VID 3533 · PID 5A11")
                if model.usbDevices.isEmpty {
                    Text("当前未检测到 P1。请接入 USB 后刷新。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.usbDevices) { device in
                        LabeledContent(device.productName, value: device.locationID.map { String(format: "位置 %08X", $0) } ?? "已连接")
                    }
                }
                HStack {
                    Button("刷新连接", systemImage: "arrow.clockwise") { model.refreshUSBDevices() }
                    Button("读取状态", systemImage: "waveform.path.ecg") { model.refreshPrinterStatus() }
                        .disabled(model.usbDevices.isEmpty)
                    Button("验证打印通道", systemImage: "checkmark.circle") { model.verifyUSBInterface() }
                        .disabled(model.usbDevices.isEmpty || model.isVerifyingUSB)
                    Button("打印校准页…", systemImage: "printer") { model.prepareTestPrint() }
                        .disabled(model.usbDevices.isEmpty)
                }
                if let status = model.printerPortStatus {
                    LabeledContent("端口状态", value: status.displayName)
                }
            }
            Section("纸张与打印") {
                Picker("纸张类型", selection: $model.paperMode) {
                    ForEach(P1PaperMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if model.paperMode != .continuous {
                    Stepper(
                        "间隙长度：\(model.gapLengthMM) mm",
                        value: $model.gapLengthMM,
                        in: 1...10
                    )
                }
                Picker("打印浓度", selection: $model.printDarkness) {
                    Text("跟随打印机").tag(0)
                    Text("最淡 · 1").tag(1)
                    Text("正常 · 6").tag(6)
                    Text("较浓 · 10").tag(10)
                    Text("最浓 · 15").tag(15)
                }
                Picker("打印速度", selection: $model.printSpeed) {
                    Text("跟随打印机").tag(0)
                    Text("最慢 · 1").tag(1)
                    Text("正常 · 3").tag(3)
                    Text("最快 · 5").tag(5)
                }
                Stepper("打印份数：\(model.printCopies)", value: $model.printCopies, in: 1...99)
                Button("校准纸张间隙…", systemImage: "arrow.up.and.down.text.horizontal") {
                    model.preparePaperCalibration()
                }
                .disabled(!model.hasConnectedPrinter || model.paperMode == .continuous)
                Text("分页协议会提交页高和间隙长度，并在页结束时由传感器定位下一张标签。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("蓝牙") {
                HStack {
                    Text(bluetoothStateText)
                    Spacer()
                    Button("扫描") { model.bluetoothDiscovery.startScan() }
                        .disabled(model.bluetoothDiscovery.state == .scanning)
                    Button("停止") { model.bluetoothDiscovery.stopScan() }
                        .disabled(model.bluetoothDiscovery.state != .scanning)
                }
                if model.bluetoothDiscovery.peripherals.isEmpty {
                    Text("尚未发现蓝牙设备。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.bluetoothDiscovery.peripherals) { device in
                        HStack {
                            Image(systemName: bluetoothSignalIcon(device.rssi))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text("信号 \(device.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.bluetoothDiscovery.connectedID == device.id {
                                Button("断开连接") {
                                    model.bluetoothDiscovery.disconnect()
                                }
                            } else {
                                Button("连接") {
                                    model.bluetoothDiscovery.connect(to: device.id)
                                }
                                .disabled(model.bluetoothDiscovery.isConnecting)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("打印机")
        .task {
            if model.usbDevices.isEmpty {
                model.refreshUSBDevices()
            }
        }
        .alert("确认打印校准页", isPresented: Binding(
            get: {
                model.pendingPrint?.source == .calibration
                    || model.pendingPrint?.source == .paperCalibration
            },
            set: { if !$0 { model.cancelPendingPrint() } }
        )) {
            Button("取消", role: .cancel) { model.cancelPendingPrint() }
            Button("确认打印") { model.confirmPendingPrint() }
        } message: {
            Text("将向德佟 P1 发送“\(model.pendingPrint?.name ?? "校准任务")”。纸张会移动，请确认纸卷安装正确。")
        }
    }

    private var bluetoothStateText: String {
        switch model.bluetoothDiscovery.state {
        case .disconnected: "未扫描"
        case .scanning: "正在扫描…"
        case .connecting(let name): "正在连接 \(name)…"
        case .connected(let name): "已连接 \(name)"
        case .failed(let reason): reason
        }
    }

    private var displayedDeviceStatus: P1DeviceStatus? {
        if bluetoothDiscovery.isConnected {
            return bluetoothDiscovery.latestDeviceStatus ?? model.deviceStatus
        }
        return model.deviceStatus
    }

    private func statusIcon(_ status: P1DeviceStatus) -> String {
        switch status.severity {
        case .ready: "checkmark.circle.fill"
        case .warning: "thermometer.medium"
        case .error: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func statusColor(_ status: P1DeviceStatus) -> Color {
        switch status.severity {
        case .ready: .green
        case .warning: .orange
        case .error: .red
        case .unknown: .secondary
        }
    }

    private func bluetoothSignalIcon(_ rssi: Int) -> String {
        switch rssi {
        case (-60)...: "wifi"
        case -75 ..< -60: "wifi.exclamationmark"
        default: "antenna.radiowaves.left.and.right.slash"
        }
    }
}
