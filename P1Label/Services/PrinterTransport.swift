@preconcurrency import CoreBluetooth
import Foundation

enum PrinterConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting(String)
    case connected(String)
    case failed(String)
}

protocol PrinterTransport: Sendable {
    var transportName: String { get }
    func send(_ data: Data) async throws
    func disconnect() async
}

enum PrinterTransportError: LocalizedError {
    case noDevice
    case busy
    case bluetoothNotReady
    case noWritableCharacteristic
    case disconnected
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .noDevice: "没有已连接的 P1。"
        case .busy: "打印机正在接收上一项任务。"
        case .bluetoothNotReady: "蓝牙打印通道尚未准备好。"
        case .noWritableCharacteristic: "已连接设备，但没有发现可写入的蓝牙打印通道。"
        case .disconnected: "蓝牙打印机已断开连接。"
        case .unsupported(let message): message
        }
    }
}

@MainActor
final class BluetoothDiscovery: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var state: PrinterConnectionState = .disconnected
    @Published private(set) var peripherals: [DiscoveredPeripheral] = []
    @Published private(set) var latestDeviceStatus: P1DeviceStatus?
    @Published private(set) var lastTransferByteCount = 0
    private var manager: CBCentralManager?
    private var scanRequested = false
    private var scanTimeout: Task<Void, Never>?
    private var nativePeripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withoutResponse
    private var pendingServiceUUIDs: Set<CBUUID> = []
    private var writableCandidates: [WritableCandidate] = []
    private var notifyCandidates: [CBCharacteristic] = []
    private var pendingWriteData: Data?
    private var pendingWriteOffset = 0
    private var pendingWriteContinuation: CheckedContinuation<Void, Error>?
    private var pacedWriteTask: Task<Void, Never>?
    private var statusBuffer = Data()
    private static let maximumBLEChunkLength = 180
    private static let BLEChunkInterval = Duration.milliseconds(33)
    private static let statusQuery = Data([0x1F, 0x70, 0x00, 0x88, 0x1F, 0x77, 0x00, 0x88])

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var connectedName: String? {
        if case .connected(let name) = state { return name }
        return nil
    }

    var connectedID: UUID? {
        isConnected ? connectedPeripheral?.identifier : nil
    }

    var isConnecting: Bool {
        if case .connecting = state { return true }
        return false
    }

    func startScan() {
        guard !scanRequested else { return }
        switch CBCentralManager.authorization {
        case .denied:
            state = .failed("蓝牙权限已关闭，请在系统设置的“隐私与安全性”中允许 P1 Label。")
            return
        case .restricted:
            state = .failed("此 Mac 不允许使用蓝牙。")
            return
        case .allowedAlways, .notDetermined:
            break
        @unknown default:
            break
        }

        scanRequested = true
        peripherals.removeAll()
        state = .scanning
        if manager == nil {
            // Creating CBCentralManager is the operation that can trigger the
            // system permission prompt, so defer it until the user presses Scan.
            manager = CBCentralManager(delegate: self, queue: .main)
        } else {
            beginScanIfReady()
        }
    }

    func stopScan() {
        scanRequested = false
        scanTimeout?.cancel()
        scanTimeout = nil
        manager?.stopScan()
        if case .scanning = state { state = .disconnected }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch central.state {
            case .poweredOn:
                beginScanIfReady()
            case .poweredOff:
                scanRequested = false
                state = .failed("请先打开 Mac 蓝牙。")
            case .unauthorized:
                scanRequested = false
                state = .failed("P1 Label 没有蓝牙权限。")
            case .unsupported:
                scanRequested = false
                state = .failed("此 Mac 不支持蓝牙低功耗。")
            case .resetting:
                state = .scanning
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let entry = DiscoveredPeripheral(
            id: peripheral.identifier,
            name: advertisedName ?? peripheral.name ?? "未命名蓝牙设备",
            rssi: RSSI.intValue
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            nativePeripherals[peripheral.identifier] = peripheral
            if let index = peripherals.firstIndex(where: { $0.id == entry.id }) {
                peripherals[index] = entry
            } else {
                peripherals.append(entry)
            }
            peripherals.sort {
                let lhsIsP1 = $0.name.localizedCaseInsensitiveContains("P1")
                let rhsIsP1 = $1.name.localizedCaseInsensitiveContains("P1")
                if lhsIsP1 != rhsIsP1 { return lhsIsP1 }
                return $0.rssi > $1.rssi
            }
        }
    }

    func connect(to id: UUID) {
        guard let peripheral = nativePeripherals[id] else {
            state = .failed("设备已离开扫描范围，请重新扫描。")
            return
        }
        guard let manager, manager.state == .poweredOn else {
            state = .failed("蓝牙尚未准备好，请重新扫描。")
            return
        }
        stopScan()
        if let connectedPeripheral, connectedPeripheral.identifier != id {
            manager.cancelPeripheralConnection(connectedPeripheral)
        }
        writeCharacteristic = nil
        notifyCharacteristic = nil
        latestDeviceStatus = nil
        peripheral.delegate = self
        state = .connecting(displayName(for: peripheral))
        manager.connect(peripheral, options: nil)
    }

    func disconnect() {
        finishPendingWrite(throwing: PrinterTransportError.disconnected)
        guard let connectedPeripheral else {
            state = .disconnected
            return
        }
        manager?.cancelPeripheralConnection(connectedPeripheral)
    }

    func send(_ data: Data) async throws {
        guard let connectedPeripheral,
              connectedPeripheral.state == .connected,
              writeCharacteristic != nil else {
            throw PrinterTransportError.bluetoothNotReady
        }
        guard pendingWriteContinuation == nil else {
            throw PrinterTransportError.busy
        }
        guard !data.isEmpty else { return }

        try await withCheckedThrowingContinuation { continuation in
            pendingWriteData = data
            pendingWriteOffset = 0
            pendingWriteContinuation = continuation
            writeNextChunk()
        }
    }

    func requestPrinterStatus() async throws -> P1DeviceStatus? {
        latestDeviceStatus = nil
        try await send(Self.statusQuery)
        try? await Task.sleep(for: .milliseconds(350))
        return latestDeviceStatus
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectedPeripheral = peripheral
            peripheral.delegate = self
            state = .connecting("\(displayName(for: peripheral)) · 正在准备打印通道")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.connectedPeripheral = nil
            self?.writeCharacteristic = nil
            self?.notifyCharacteristic = nil
            self?.state = .failed(error?.localizedDescription ?? "无法连接蓝牙打印机。")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            finishPendingWrite(throwing: error ?? PrinterTransportError.disconnected)
            connectedPeripheral = nil
            writeCharacteristic = nil
            notifyCharacteristic = nil
            latestDeviceStatus = nil
            state = error.map { .failed("蓝牙连接已中断：\($0.localizedDescription)") } ?? .disconnected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                failSetup(error.localizedDescription)
                return
            }
            guard let services = peripheral.services, !services.isEmpty else {
                failSetup(PrinterTransportError.noWritableCharacteristic.localizedDescription)
                return
            }
            pendingServiceUUIDs = Set(services.map(\.uuid))
            writableCandidates.removeAll()
            notifyCandidates.removeAll()
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                failSetup(error.localizedDescription)
                return
            }
            pendingServiceUUIDs.remove(service.uuid)
            for characteristic in service.characteristics ?? [] {
                let type: CBCharacteristicWriteType?
                if characteristic.properties.contains(.writeWithoutResponse) {
                    type = .withoutResponse
                } else if characteristic.properties.contains(.write) {
                    type = .withResponse
                } else {
                    type = nil
                }
                if let type {
                    writableCandidates.append(.init(
                        characteristic: characteristic,
                        type: type,
                        priority: writePriority(service: service, characteristic: characteristic)
                    ))
                }
                if characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate) {
                    notifyCandidates.append(characteristic)
                }
            }
            if pendingServiceUUIDs.isEmpty {
                if let candidate = writableCandidates.max(by: { $0.priority < $1.priority }) {
                    notifyCharacteristic = preferredNotifyCharacteristic(
                        for: candidate.characteristic,
                        candidates: notifyCandidates
                    )
                    completeSetup(
                        peripheral: peripheral,
                        characteristic: candidate.characteristic,
                        type: candidate.type
                    )
                } else {
                    failSetup(PrinterTransportError.noWritableCharacteristic.localizedDescription)
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                finishPendingWrite(throwing: error)
            } else {
                scheduleNextChunk()
            }
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self, pacedWriteTask == nil else { return }
            writeNextChunk()
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self, error == nil, let value = characteristic.value else { return }
            statusBuffer.append(value)
            parseStatusFrames()
        }
    }

    private func beginScanIfReady() {
        guard scanRequested, let manager, manager.state == .poweredOn, !manager.isScanning else { return }
        manager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanTimeout?.cancel()
        scanTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.scanRequested else { return }
                self.stopScan()
            }
        }
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripherals.first(where: { $0.id == peripheral.identifier })?.name
            ?? peripheral.name
            ?? "P1"
    }

    private func completeSetup(
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType
    ) {
        connectedPeripheral = peripheral
        writeCharacteristic = characteristic
        writeType = type
        if let notifyCharacteristic {
            peripheral.setNotifyValue(true, for: notifyCharacteristic)
        }
        pendingServiceUUIDs.removeAll()
        writableCandidates.removeAll()
        notifyCandidates.removeAll()
        state = .connected(displayName(for: peripheral))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            _ = try? await self?.requestPrinterStatus()
        }
    }

    private func failSetup(_ reason: String?) {
        let message = reason ?? PrinterTransportError.noWritableCharacteristic.localizedDescription
        if let connectedPeripheral {
            manager?.cancelPeripheralConnection(connectedPeripheral)
        }
        pendingServiceUUIDs.removeAll()
        writableCandidates.removeAll()
        notifyCandidates.removeAll()
        state = .failed(message)
    }

    private func writePriority(service: CBService, characteristic: CBCharacteristic) -> Int {
        let serviceUUID = service.uuid.uuidString.uppercased()
        let characteristicUUID = characteristic.uuid.uuidString.uppercased()
        var priority = 0
        if characteristicUUID == "FFE1" { priority += 1_000 }
        if serviceUUID == "FFE0"
            || serviceUUID == "18F0"
            || serviceUUID == "49535343-FE7D-4AE5-8FA9-9FAFD205E455"
            || serviceUUID == "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2" {
            priority += 500
        }
        if characteristic.properties.contains(.writeWithoutResponse) { priority += 10 }
        return priority
    }

    private func writeNextChunk() {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic,
              let data = pendingWriteData else { return }
        let maximum = max(
            1,
            min(
                Self.maximumBLEChunkLength,
                peripheral.maximumWriteValueLength(for: writeType)
            )
        )

        if writeType == .withoutResponse {
            guard pendingWriteOffset < data.count else {
                finishPendingWrite()
                return
            }
            guard peripheral.canSendWriteWithoutResponse else { return }
            let end = min(data.count, pendingWriteOffset + maximum)
            peripheral.writeValue(
                data.subdata(in: pendingWriteOffset..<end),
                for: characteristic,
                type: .withoutResponse
            )
            pendingWriteOffset = end
            if pendingWriteOffset >= data.count {
                finishPendingWrite()
            } else {
                scheduleNextChunk()
            }
            return
        }

        guard pendingWriteOffset < data.count else {
            finishPendingWrite()
            return
        }
        let end = min(data.count, pendingWriteOffset + maximum)
        peripheral.writeValue(
            data.subdata(in: pendingWriteOffset..<end),
            for: characteristic,
            type: .withResponse
        )
        pendingWriteOffset = end
    }

    private func scheduleNextChunk() {
        guard pendingWriteData != nil, pacedWriteTask == nil else { return }
        pacedWriteTask = Task { [weak self] in
            try? await Task.sleep(for: Self.BLEChunkInterval)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.pacedWriteTask = nil
                self.writeNextChunk()
            }
        }
    }

    private func finishPendingWrite(throwing error: Error? = nil) {
        pacedWriteTask?.cancel()
        pacedWriteTask = nil
        let continuation = pendingWriteContinuation
        let transferredByteCount = pendingWriteData?.count ?? 0
        pendingWriteContinuation = nil
        pendingWriteData = nil
        pendingWriteOffset = 0
        if let error {
            continuation?.resume(throwing: error)
        } else {
            lastTransferByteCount = transferredByteCount
            continuation?.resume()
        }
    }

    private func preferredNotifyCharacteristic(
        for writeCharacteristic: CBCharacteristic,
        candidates: [CBCharacteristic]
    ) -> CBCharacteristic? {
        if let matching = candidates.first(where: {
            $0.service?.uuid == writeCharacteristic.service?.uuid
        }) {
            return matching
        }
        return candidates.first
    }

    private func parseStatusFrames() {
        while let start = statusBuffer.firstIndex(of: 0x1F) {
            if start > statusBuffer.startIndex {
                statusBuffer.removeSubrange(statusBuffer.startIndex..<start)
            }
            guard let end = statusBuffer.dropFirst().firstIndex(of: 0x88) else {
                if statusBuffer.count > 256 { statusBuffer.removeAll() }
                return
            }
            let frame = Data(statusBuffer[statusBuffer.startIndex...end])
            statusBuffer.removeSubrange(statusBuffer.startIndex...end)
            guard frame.count >= 5, frame[1] == 0x70 else { continue }
            latestDeviceStatus = .sdk(code: frame[3])
        }
    }
}

private struct WritableCandidate {
    let characteristic: CBCharacteristic
    let type: CBCharacteristicWriteType
    let priority: Int
}

struct DiscoveredPeripheral: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let rssi: Int
}
