import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var document = LabelDocument.blank {
        didSet { documentDidChange(from: oldValue) }
    }
    var selectedLayerID: UUID?
    var selectedLayerIDs: Set<UUID> = []
    private var storedPrintStatus = "尚未连接打印机"
    var printStatus: String {
        get { storedPrintStatus }
        set { storedPrintStatus = Self.normalizedPrinterStatus(newValue) }
    }
    var usbDevices: [P1USBDevice] = []
    var isVerifyingUSB = false
    private(set) var lastCalibrationPrintOffsetX = 0.0
    private(set) var lastCalibrationPrintOffsetY = 0.0
    var printerPortStatus: P1PrinterPortStatus?
    var deviceStatus: P1DeviceStatus?
    var batchRecords: [[String: String]] = []
    var serialStart = 1
    var serialCount = 10
    var currentDocumentURL: URL?
    var pendingPrint: PendingPrint?
    var paperMode: P1PaperMode {
        didSet { preferences.set(paperMode.rawValue, forKey: "paperMode") }
    }
    var gapLengthMM: Int {
        didSet { preferences.set(gapLengthMM, forKey: "gapLengthMM") }
    }
    var printDarkness: Int {
        didSet { preferences.set(printDarkness, forKey: "printDarkness") }
    }
    var printSpeed: Int {
        didSet { preferences.set(printSpeed, forKey: "printSpeed") }
    }
    var printCopies: Int {
        didSet { preferences.set(printCopies, forKey: "printCopies") }
    }
    var printInverted: Bool {
        didSet { preferences.set(printInverted, forKey: "printInverted") }
    }
    var calibrationOffsetX: Double {
        didSet {
            let normalized = Self.normalizedCalibrationOffset(calibrationOffsetX)
            if calibrationOffsetX != normalized {
                calibrationOffsetX = normalized
            }
            preferences.set(normalized, forKey: "printOffsetX")
        }
    }
    var calibrationOffsetY: Double {
        didSet {
            let normalized = Self.normalizedCalibrationOffset(calibrationOffsetY)
            if calibrationOffsetY != normalized {
                calibrationOffsetY = normalized
            }
            preferences.set(normalized, forKey: "printOffsetY")
        }
    }
    let bluetoothDiscovery = BluetoothDiscovery()
    private let usbTransport = P1USBTransport()
    private let preferences: UserDefaults
    @ObservationIgnored private var undoStack: [LabelDocument] = []
    @ObservationIgnored private var redoStack: [LabelDocument] = []
    @ObservationIgnored private var suppressHistory = false
    @ObservationIgnored private var lastHistoryDate = Date.distantPast
    @ObservationIgnored private var lastSavedDocument = LabelDocument.blank
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var printerStatusTask: Task<Void, Never>?
    @ObservationIgnored private var printCompletionResetTask: Task<Void, Never>?
    @ObservationIgnored private var isAutomaticallyDiscoveringPrinter = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var hasUnsavedChanges = false

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        calibrationOffsetX = Self.normalizedCalibrationOffset(
            preferences.double(forKey: "printOffsetX")
        )
        calibrationOffsetY = Self.normalizedCalibrationOffset(
            preferences.double(forKey: "printOffsetY")
        )
        gapLengthMM = preferences.object(forKey: "gapLengthMM") == nil
            ? 2
            : preferences.integer(forKey: "gapLengthMM")
        printDarkness = preferences.integer(forKey: "printDarkness")
        printSpeed = preferences.integer(forKey: "printSpeed")
        printCopies = max(1, preferences.integer(forKey: "printCopies"))
        printInverted = preferences.bool(forKey: "printInverted")
        if let savedMode = preferences.object(forKey: "paperMode") as? NSNumber,
           let mode = P1PaperMode(rawValue: savedMode.intValue) {
            paperMode = mode
        } else {
            paperMode = .gap
        }
        selectedLayerID = nil
    }

    var selectedLayerIsLocked: Bool {
        selectedLayers.contains(where: \.isLocked)
    }

    var hasNonZeroPrintOffset: Bool {
        abs(calibrationOffsetX) > 0.000_1 || abs(calibrationOffsetY) > 0.000_1
    }

    var hasConnectedPrinter: Bool {
        !usbDevices.isEmpty || bluetoothDiscovery.isConnected
    }

    var activePrintConnectionName: String {
        if let name = bluetoothDiscovery.connectedName {
            return "蓝牙 · \(name)"
        }
        return usbDevices.isEmpty ? "未连接" : "USB · DeTong P1"
    }

    var documentPrintConfirmationMessage: String {
        var parts = ["将通过\(activePrintConnectionName)发送“\(pendingPrint?.name ?? "标签")”。"]
        if hasNonZeroPrintOffset {
            parts.append(
                "打印偏移：左右 \(formatMillimeters(calibrationOffsetX)) mm，上下 \(formatMillimeters(calibrationOffsetY)) mm。"
            )
        }
        return parts.joined(separator: " ")
    }

    var canAlignSelection: Bool {
        !selectedLayerIDs.isEmpty && !selectedLayerIsLocked
    }

    var hasSelection: Bool {
        !effectiveSelectedLayerIDs.isEmpty
    }

    private var selectedLayers: [LabelLayer] {
        document.layers.filter { effectiveSelectedLayerIDs.contains($0.id) }
    }

    private var effectiveSelectedLayerIDs: Set<UUID> {
        if !selectedLayerIDs.isEmpty { return selectedLayerIDs }
        return Set(selectedLayerID.map { [$0] } ?? [])
    }

    func newDocument() {
        replaceDocumentWithoutHistory(.blank)
        selectedLayerID = nil
        selectedLayerIDs = []
        currentDocumentURL = nil
        resetHistory(markSaved: true)
        printStatus = "已新建标签"
    }

    func requestSave() {
        guard let currentDocumentURL else {
            requestSaveAs()
            return
        }
        saveDocument(to: currentDocumentURL)
    }

    func requestSaveAs() {
        FilePanelService.chooseSaveLocation(
            defaultName: document.name,
            isExportCopy: false
        ) { [weak self] url in
            guard let self, let url else { return }
            saveDocument(to: url)
        }
    }

    func requestOpenDocument() {
        FilePanelService.chooseLabel { [weak self] url in
            guard let self, let url else { return }
            openDocument(from: url)
        }
    }

    func requestExportCopy() {
        FilePanelService.chooseSaveLocation(
            defaultName: document.name,
            isExportCopy: true
        ) { [weak self] url in
            guard let self, let url else { return }
            exportDocumentCopy(to: url)
        }
    }

    func requestImportCSV() {
        FilePanelService.chooseCSV { [weak self] url in
            guard let self, let url else { return }
            importCSV(from: url)
        }
    }

    func requestImportImage() {
        FilePanelService.chooseImage { [weak self] url in
            guard let self, let url else { return }
            importImage(from: url)
        }
    }

    func loadDocument(_ document: LabelDocument, from url: URL) {
        replaceDocumentWithoutHistory(document)
        selectedLayerID = document.layers.last?.id
        selectedLayerIDs = Set(selectedLayerID.map { [$0] } ?? [])
        currentDocumentURL = url
        resetHistory(markSaved: true)
        printStatus = "已打开标签“\(document.name)”。"
    }

    @discardableResult
    func saveDocument(to url: URL) -> Bool {
        do {
            try withSecurityScopedAccess(to: url) {
                try encodedDocument().write(to: url, options: .atomic)
            }
            currentDocumentURL = url
            markCurrentDocumentSaved()
            printStatus = "已保存“\(url.lastPathComponent)”"
            return true
        } catch {
            printStatus = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func exportDocumentCopy(to url: URL) -> Bool {
        do {
            try withSecurityScopedAccess(to: url) {
                try encodedDocument().write(to: url, options: .atomic)
            }
            printStatus = "已导出标签副本“\(url.lastPathComponent)”"
            return true
        } catch {
            printStatus = "导出失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func openDocument(from url: URL) -> Bool {
        do {
            let data = try withSecurityScopedAccess(to: url) {
                try Data(contentsOf: url)
            }
            let opened = try JSONDecoder().decode(LabelDocument.self, from: data)
            loadDocument(opened, from: url)
            return true
        } catch {
            printStatus = "打开失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func importCSV(from url: URL) -> Bool {
        do {
            let data = try withSecurityScopedAccess(to: url) {
                try Data(contentsOf: url)
            }
            return loadBatchCSV(data)
        } catch {
            printStatus = "CSV 导入失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func importImage(from url: URL) -> Bool {
        do {
            let data = try withSecurityScopedAccess(to: url) {
                try Data(contentsOf: url)
            }
            try addImageLayer(
                data: data,
                name: url.deletingPathExtension().lastPathComponent
            )
            return true
        } catch {
            printStatus = "导入图片失败：\(error.localizedDescription)"
            return false
        }
    }

    private func encodedDocument() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) rethrows -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    func addTextLayer() {
        var layer = LabelLayer.text("文字", x: 4, y: 4, fontSizeMM: 3)
        layer.name = "文本"
        document.layers.append(layer)
        selectedLayerID = layer.id
        selectedLayerIDs = [layer.id]
    }

    func addShapeLayer(_ kind: LabelLayer.Kind) {
        let layer = LabelLayer.shape(kind, x: 6, y: 6)
        document.layers.append(layer)
        selectedLayerID = layer.id
        selectedLayerIDs = [layer.id]
    }

    func addImageLayer(data: Data, name: String) throws {
        guard let aspectRatio = LabelImageProcessor.sourceAspectRatio(data: data) else {
            throw AppModelError.invalidImage
        }
        let layer = LabelLayer.image(
            data,
            name: name,
            x: 4,
            y: 4,
            aspectRatio: aspectRatio
        )
        document.layers.append(layer)
        selectedLayerID = layer.id
        selectedLayerIDs = [layer.id]
        printStatus = "已导入图片“\(name)”。"
    }

    func duplicateSelectedLayer() {
        guard copySelectedLayers() else { return }
        pasteSelectedLayers()
    }

    @discardableResult
    func copySelectedLayers() -> Bool {
        let layers = document.layers.filter { effectiveSelectedLayerIDs.contains($0.id) }
        guard !layers.isEmpty, let data = try? JSONEncoder().encode(layers) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .p1LabelLayers)
        return true
    }

    func cutSelectedLayers() {
        guard !selectedLayerIsLocked, copySelectedLayers() else { return }
        deleteSelectedLayer()
    }

    func pasteSelectedLayers() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .p1LabelLayers),
           let decoded = try? JSONDecoder().decode([LabelLayer].self, from: data),
           !decoded.isEmpty {
            var pasted: [LabelLayer] = []
            for var layer in decoded {
                layer.id = UUID()
                layer.name += " 副本"
                layer.x = min(max(0, layer.x + 2), max(0, document.paper.widthMM - layer.width))
                layer.y = min(max(0, layer.y + 2), max(0, document.paper.heightMM - layer.height))
                pasted.append(layer)
            }
            document.layers.append(contentsOf: pasted)
            selectedLayerIDs = Set(pasted.map(\.id))
            selectedLayerID = pasted.last?.id
            return
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let layer = LabelLayer.text(text, x: 4, y: 4, fontSizeMM: 3)
            document.layers.append(layer)
            selectedLayerID = layer.id
            selectedLayerIDs = [layer.id]
        }
    }

    func deleteSelectedLayer() {
        let deletableIDs = effectiveSelectedLayerIDs.filter { id in
            document.layers.first(where: { $0.id == id })?.isLocked == false
        }
        guard !deletableIDs.isEmpty else { return }
        document.layers.removeAll { deletableIDs.contains($0.id) }
        selectedLayerID = document.layers.last?.id
        selectedLayerIDs = Set(selectedLayerID.map { [$0] } ?? [])
    }

    func selectAllLayers() {
        selectedLayerIDs = Set(document.layers.map(\.id))
        selectedLayerID = document.layers.last?.id
    }

    func clearLayerSelection() {
        selectedLayerID = nil
        selectedLayerIDs = []
    }

    func toggleSelectedLayersLocked() {
        let targetIDs = effectiveSelectedLayerIDs
        guard !targetIDs.isEmpty else { return }
        let shouldLock = document.layers
            .filter { targetIDs.contains($0.id) }
            .contains { !$0.isLocked }
        for index in document.layers.indices where targetIDs.contains(document.layers[index].id) {
            document.layers[index].isLocked = shouldLock
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        replaceDocumentWithoutHistory(previous)
        repairSelection()
        lastHistoryDate = .distantPast
        updateHistoryState()
        scheduleAutosave()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        replaceDocumentWithoutHistory(next)
        repairSelection()
        lastHistoryDate = .distantPast
        updateHistoryState()
        scheduleAutosave()
    }

    private func documentDidChange(from oldValue: LabelDocument) {
        guard !suppressHistory, oldValue != document else { return }
        let now = Date()
        if undoStack.isEmpty || now.timeIntervalSince(lastHistoryDate) > 0.45 {
            undoStack.append(oldValue)
            if undoStack.count > 100 {
                undoStack.removeFirst(undoStack.count - 100)
            }
        }
        lastHistoryDate = now
        redoStack.removeAll()
        canUndo = !undoStack.isEmpty
        canRedo = false
        // A direct edit is always dirty. Comparing the complete document to
        // the last saved copy here made every drag and keystroke walk image
        // payloads on the main thread. Undo/redo still perform the exact check.
        hasUnsavedChanges = true
        scheduleAutosave()
    }

    private func replaceDocumentWithoutHistory(_ replacement: LabelDocument) {
        suppressHistory = true
        document = replacement
        suppressHistory = false
    }

    private func resetHistory(markSaved: Bool) {
        undoStack.removeAll()
        redoStack.removeAll()
        lastHistoryDate = .distantPast
        if markSaved {
            lastSavedDocument = document
        }
        updateHistoryState()
    }

    private func repairSelection() {
        let existingIDs = Set(document.layers.map(\.id))
        selectedLayerIDs.formIntersection(existingIDs)
        if let selectedLayerID, !existingIDs.contains(selectedLayerID) {
            self.selectedLayerID = nil
        }
    }

    private func updateHistoryState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        hasUnsavedChanges = document != lastSavedDocument
    }

    private func markCurrentDocumentSaved() {
        lastSavedDocument = document
        hasUnsavedChanges = false
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard currentDocumentURL != nil else { return }
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let url = self.currentDocumentURL else { return }
            self.saveDocument(to: url)
        }
    }

    func prepareTestPrint() {
        guard P1PrintGeometry.supports(document.paper) else {
            pendingPrint = nil
            printStatus = "无法生成定位标签：纸张尺寸必须大于 0，宽度不能超过 48 mm。"
            return
        }
        let offsetX = P1PrintGeometry.dots(forMillimeters: calibrationOffsetX)
        let offsetY = P1PrintGeometry.dots(forMillimeters: calibrationOffsetY)
        let raster = P1Raster.positioningCalibrationSheet(
            width: P1Protocol.printWidthBytes * 8,
            paperWidth: document.paper.pixelWidth,
            height: document.paper.pixelHeight
        ).offsetBy(x: offsetX, y: offsetY)
        lastCalibrationPrintOffsetX = calibrationOffsetX
        lastCalibrationPrintOffsetY = calibrationOffsetY
        pendingPrint = .init(
            data: repeatedPrintData(for: raster, copies: 1),
            name: "P1 定位校准标签 \(document.paper.displayName)",
            source: .calibration
        )
        printStatus = "定位校准标签已生成，等待确认。"
    }

    func preparePaperCalibration() {
        guard P1PrintGeometry.supports(document.paper) else {
            pendingPrint = nil
            printStatus = "无法校准纸张：纸张尺寸必须大于 0，宽度不能超过 48 mm。"
            return
        }
        let height = max(1, Int((document.paper.heightMM * 8).rounded()))
        let blank = P1Raster(width: P1Protocol.printWidthBytes * 8, height: height)
        pendingPrint = .init(
            data: repeatedPrintData(for: blank, copies: 1),
            name: "P1 纸张间隙校准",
            source: .paperCalibration
        )
        printStatus = "纸张校准任务已生成，等待确认。"
    }

    func prepareDocumentPrint() {
        do {
            let raster = try LabelRasterizer.raster(
                document: document,
                horizontalOffsetMM: calibrationOffsetX,
                verticalOffsetMM: calibrationOffsetY
            )
            pendingPrint = .init(
                data: repeatedPrintData(for: raster, copies: printCopies),
                name: printCopies == 1 ? document.name : "\(document.name) × \(printCopies)",
                source: .document
            )
            printStatus = "标签已生成，等待确认。"
        } catch {
            pendingPrint = nil
            printStatus = error.localizedDescription
        }
    }

    @discardableResult
    func loadBatchCSV(_ data: Data) -> Bool {
        do {
            batchRecords = try CSVBatchParser.records(from: data)
            printStatus = "已载入 \(batchRecords.count) 条批量数据。"
            return true
        } catch {
            printStatus = "CSV 导入失败：\(error.localizedDescription)"
            return false
        }
    }

    func clearBatchData() {
        batchRecords = []
        printStatus = "已清除 CSV 批量数据。"
    }

    func prepareBatchPrint() {
        let records: [[String: String]]
        if batchRecords.isEmpty {
            records = (0..<max(1, serialCount)).map {
                ["序号": String(serialStart + $0)]
            }
        } else {
            records = batchRecords.enumerated().map { index, value in
                var record = value
                record["序号"] = String(serialStart + index)
                return record
            }
        }

        do {
            var data = Data()
            for record in records {
                var renderedDocument = document
                for index in renderedDocument.layers.indices {
                    for (key, value) in record {
                        renderedDocument.layers[index].text = renderedDocument.layers[index].text
                            .replacingOccurrences(of: "{{\(key)}}", with: value)
                    }
                }
                let raster = try LabelRasterizer.raster(
                    document: renderedDocument,
                    horizontalOffsetMM: calibrationOffsetX,
                    verticalOffsetMM: calibrationOffsetY
                )
                data += repeatedPrintData(for: raster, copies: printCopies)
            }
            pendingPrint = .init(
                data: data,
                name: "批量标签 × \(records.count)",
                source: .document
            )
            printStatus = "已生成 \(records.count) 张批量标签，等待确认。"
        } catch {
            pendingPrint = nil
            printStatus = error.localizedDescription
        }
    }

    private func repeatedPrintData(for raster: P1Raster, copies: Int) -> Data {
        let oneJob = P1Protocol.printJob(
            raster: printInverted ? raster.inverted() : raster,
            paperMode: paperMode,
            gapLengthMM: gapLengthMM,
            darkness: printDarkness,
            speed: printSpeed
        )
        var result = Data()
        for _ in 0..<max(1, copies) {
            result += oneJob
        }
        return result
    }

    func refreshUSBDevices() {
        usbDevices = P1USBDiscovery.connectedDevices()
        guard !usbDevices.isEmpty else {
            printerPortStatus = nil
            deviceStatus = nil
            printStatus = "未检测到德佟 P1，请检查 USB 连接。"
            return
        }
        printStatus = "已通过 USB 检测到 P1"
    }

    /// Looks for a USB P1 without triggering the macOS Bluetooth permission
    /// prompt. Bluetooth discovery remains an explicit user action.
    func discoverPrinterAutomatically(
        interval: Duration = .seconds(5),
        maximumDuration: Duration = .seconds(180)
    ) async {
        guard !hasConnectedPrinter, !isAutomaticallyDiscoveringPrinter else { return }
        isAutomaticallyDiscoveringPrinter = true
        defer { isAutomaticallyDiscoveringPrinter = false }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: maximumDuration)
        while !Task.isCancelled, clock.now < deadline, !hasConnectedPrinter {
            refreshUSBDevices()
            if hasConnectedPrinter {
                refreshPrinterStatus()
                return
            }
            do {
                try await clock.sleep(for: interval)
            } catch {
                return
            }
        }
    }

    func verifyUSBInterface() {
        guard !usbDevices.isEmpty, !isVerifyingUSB else { return }
        isVerifyingUSB = true
        printStatus = "正在验证 USB 打印通道…"
        Task {
            defer { isVerifyingUSB = false }
            do {
                try await usbTransport.connect()
                await usbTransport.disconnect()
                printStatus = "已验证 P1 USB 打印接口。"
            } catch {
                printStatus = "已检测到 P1；\(error.localizedDescription)"
            }
        }
    }

    func refreshPrinterStatus() {
        printerStatusTask?.cancel()
        if bluetoothDiscovery.isConnected {
            printerStatusTask = Task {
                do {
                    let status = try await bluetoothDiscovery.requestPrinterStatus() ?? .unknown
                    guard !Task.isCancelled else { return }
                    deviceStatus = status
                    printStatus = "P1 状态：\(deviceStatus?.title ?? "状态未知")"
                } catch {
                    guard !Task.isCancelled else { return }
                    deviceStatus = .unknown
                    printStatus = "读取蓝牙状态失败：\(error.localizedDescription)"
                }
            }
            return
        }
        guard !usbDevices.isEmpty else {
            printerPortStatus = nil
            deviceStatus = nil
            printStatus = "未检测到德佟 P1。"
            return
        }
        printerStatusTask = Task {
            do {
                let status = try await usbTransport.readPortStatus()
                guard !Task.isCancelled else { return }
                printerPortStatus = status
                deviceStatus = .usb(status)
                printStatus = "P1 状态：\(status.displayName)"
            } catch {
                guard !Task.isCancelled else { return }
                printerPortStatus = nil
                deviceStatus = nil
                printStatus = error.localizedDescription
            }
        }
    }

    func nudgeSelectedLayer(dx: Double, dy: Double) {
        for index in document.layers.indices
        where effectiveSelectedLayerIDs.contains(document.layers[index].id) && !document.layers[index].isLocked {
            document.layers[index].x = min(
                max(0, document.layers[index].x + dx),
                max(0, document.paper.widthMM - document.layers[index].width)
            )
            document.layers[index].y = min(
                max(0, document.layers[index].y + dy),
                max(0, document.paper.heightMM - document.layers[index].height)
            )
        }
    }

    func alignSelection(_ alignment: LayerAlignment) {
        let indices = document.layers.indices.filter {
            effectiveSelectedLayerIDs.contains(document.layers[$0].id) && !document.layers[$0].isLocked
        }
        guard !indices.isEmpty else { return }
        let minX = indices.map { document.layers[$0].x }.min() ?? 0
        let maxX = indices.map { document.layers[$0].x + document.layers[$0].width }.max() ?? document.paper.widthMM
        let minY = indices.map { document.layers[$0].y }.min() ?? 0
        let maxY = indices.map { document.layers[$0].y + document.layers[$0].height }.max() ?? document.paper.heightMM

        for index in indices {
            switch alignment {
            case .left:
                document.layers[index].x = indices.count == 1 ? 0 : minX
            case .horizontalCenter:
                let center = indices.count == 1 ? document.paper.widthMM / 2 : (minX + maxX) / 2
                document.layers[index].x = center - document.layers[index].width / 2
            case .right:
                let edge = indices.count == 1 ? document.paper.widthMM : maxX
                document.layers[index].x = edge - document.layers[index].width
            case .top:
                document.layers[index].y = indices.count == 1 ? 0 : minY
            case .verticalCenter:
                let center = indices.count == 1 ? document.paper.heightMM / 2 : (minY + maxY) / 2
                document.layers[index].y = center - document.layers[index].height / 2
            case .bottom:
                let edge = indices.count == 1 ? document.paper.heightMM : maxY
                document.layers[index].y = edge - document.layers[index].height
            }
        }
    }

    func confirmPendingPrint() {
        guard let pendingPrint else { return }
        self.pendingPrint = nil
        Task {
            do {
                if bluetoothDiscovery.isConnected {
                    if let status = try await bluetoothDiscovery.requestPrinterStatus(),
                       !status.isReady {
                        deviceStatus = status
                        printStatus = "\(status.title)：\(status.detail)"
                        return
                    }
                    try await bluetoothDiscovery.send(pendingPrint.data)
                    showPrintCompletedStatus(
                        "“\(pendingPrint.name)”已通过\(activePrintConnectionName)发送 \(bluetoothDiscovery.lastTransferByteCount) 字节"
                    )
                    try? await Task.sleep(for: .milliseconds(500))
                    if let status = try? await bluetoothDiscovery.requestPrinterStatus() {
                        deviceStatus = status
                        if !status.isReady {
                            printStatus = "\(status.title)：\(status.detail)"
                        }
                    }
                } else {
                    try await usbTransport.send(pendingPrint.data)
                    showPrintCompletedStatus(
                        "“\(pendingPrint.name)”已通过\(activePrintConnectionName)发送"
                    )
                }
            } catch {
                printStatus = error.localizedDescription
            }
        }
    }

    func cancelPendingPrint() {
        guard pendingPrint != nil else { return }
        pendingPrint = nil
        printStatus = "已取消打印。"
    }

    private func formatMillimeters(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    func showPrintCompletedStatus(
        _ message: String,
        resetAfter delay: Duration = .seconds(5)
    ) {
        printCompletionResetTask?.cancel()
        printStatus = message
        let completedStatus = printStatus
        printCompletionResetTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.printStatus == completedStatus else { return }
            self.printStatus = "已就绪"
        }
    }

    static func normalizedPrinterStatus(_ status: String) -> String {
        status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。.．"))
    }

    private static func normalizedCalibrationOffset(_ value: Double) -> Double {
        P1PrintGeometry.normalizedOffsetMM(value)
    }
}

private extension NSPasteboard.PasteboardType {
    static let p1LabelLayers = NSPasteboard.PasteboardType("com.louis.p1label.layers")
}

private enum AppModelError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "无法读取该图片。请使用 PNG、JPEG、HEIC、TIFF、GIF 或 PDF 图片。"
    }
}

enum LayerAlignment {
    case left, horizontalCenter, right, top, verticalCenter, bottom
}

struct PendingPrint: Identifiable, Sendable {
    enum Source: Sendable, Equatable { case calibration, paperCalibration, document }

    let id = UUID()
    let data: Data
    let name: String
    let source: Source
}
