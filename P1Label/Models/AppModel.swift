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
    private(set) var pendingDocumentAction: PendingDocumentAction?
    var paperMode: P1PaperMode {
        didSet { preferences.set(paperMode.rawValue, forKey: "paperMode") }
    }
    var gapLengthMM: Int {
        didSet {
            let normalized = min(10, max(1, gapLengthMM))
            if gapLengthMM != normalized { gapLengthMM = normalized }
            preferences.set(normalized, forKey: "gapLengthMM")
        }
    }
    var printDarkness: Int {
        didSet {
            let normalized = min(15, max(0, printDarkness))
            if printDarkness != normalized { printDarkness = normalized }
            preferences.set(normalized, forKey: "printDarkness")
        }
    }
    var printSpeed: Int {
        didSet {
            let normalized = min(5, max(0, printSpeed))
            if printSpeed != normalized { printSpeed = normalized }
            preferences.set(normalized, forKey: "printSpeed")
        }
    }
    var printCopies: Int {
        didSet {
            let normalized = min(99, max(1, printCopies))
            if printCopies != normalized { printCopies = normalized }
            preferences.set(normalized, forKey: "printCopies")
        }
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
    let bluetoothPrinter = BluetoothPrinterController()
    let printHistory: PrintHistoryStore
    private let usbTransport = P1USBTransport()
    private let documentFiles = DocumentFileAccess()
    private let preferences: UserDefaults
    @ObservationIgnored private var history = DocumentHistory(savedDocument: .blank)
    @ObservationIgnored private var suppressHistory = false
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var documentOperationTask: Task<Void, Never>?
    @ObservationIgnored private var documentOperationID: UUID?
    @ObservationIgnored private var usbDiscoveryTask: Task<Void, Never>?
    @ObservationIgnored private var usbDiscoveryID: UUID?
    @ObservationIgnored private var printerStatusTask: Task<Void, Never>?
    @ObservationIgnored private var printCompletionResetTask: Task<Void, Never>?
    @ObservationIgnored private var printPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var printPreparationID: UUID?
    @ObservationIgnored private var printSendingTask: Task<Void, Never>?
    @ObservationIgnored private var activePrintHistoryID: UUID?
    @ObservationIgnored private var terminationCompletion: ((Bool) -> Void)?
    @ObservationIgnored private var terminationWaitTask: Task<Void, Never>?
    @ObservationIgnored private var diagnosticExportTask: Task<Void, Never>?
    @ObservationIgnored private var isAutomaticallyDiscoveringPrinter = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var hasUnsavedChanges = false
    private(set) var isSendingPrint = false

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        printHistory = PrintHistoryStore(preferences: preferences)
        calibrationOffsetX = Self.normalizedCalibrationOffset(
            preferences.double(forKey: "printOffsetX")
        )
        calibrationOffsetY = Self.normalizedCalibrationOffset(
            preferences.double(forKey: "printOffsetY")
        )
        gapLengthMM = preferences.object(forKey: "gapLengthMM") == nil
            ? 2
            : min(10, max(1, preferences.integer(forKey: "gapLengthMM")))
        printDarkness = min(15, max(0, preferences.integer(forKey: "printDarkness")))
        printSpeed = min(5, max(0, preferences.integer(forKey: "printSpeed")))
        printCopies = min(99, max(1, preferences.integer(forKey: "printCopies")))
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
        !usbDevices.isEmpty || bluetoothPrinter.isConnected
    }

    var activePrintConnectionName: String {
        if let name = bluetoothPrinter.connectedName {
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
        hasSelection && !selectedLayerIsLocked
    }

    var hasSelection: Bool {
        !effectiveSelectedLayerIDs.isEmpty
    }

    var requiresTerminationCoordination: Bool {
        hasUnsavedChanges || isSendingPrint
    }

    private var selectedLayers: [LabelLayer] {
        let selectedIDs = effectiveSelectedLayerIDs
        return document.layers.filter { selectedIDs.contains($0.id) }
    }

    private var effectiveSelectedLayerIDs: Set<UUID> {
        if !selectedLayerIDs.isEmpty { return selectedLayerIDs }
        return Set(selectedLayerID.map { [$0] } ?? [])
    }

    func requestNewDocument() {
        requestDocumentAction(.newDocument(.blank))
    }

    func requestTemplate(_ template: DocumentTemplate) {
        requestDocumentAction(.newDocument(template))
    }

    private func performNewDocument(_ template: DocumentTemplate) {
        cancelDocumentOperation()
        autosaveTask?.cancel()
        LabelPreviewCache.shared.removeAll()
        replaceDocumentWithoutHistory(template.makeDocument())
        selectedLayerID = nil
        selectedLayerIDs = []
        currentDocumentURL = nil
        resetHistory()
        printStatus = template == .blank ? "已新建标签" : "已从“\(template.displayName)”新建标签"
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
            requestDocumentAction(.open(url))
        }
    }

    func requestApplicationTermination(completion: @escaping (Bool) -> Void) {
        terminationCompletion = completion
        if isSendingPrint {
            if let activePrintHistoryID {
                cancelPrintJob(activePrintHistoryID)
            }
            let sendingTask = printSendingTask
            terminationWaitTask?.cancel()
            terminationWaitTask = Task { [weak self] in
                await sendingTask?.value
                guard !Task.isCancelled, let self else { return }
                self.terminationWaitTask = nil
                self.continueApplicationTermination()
            }
            return
        }
        continueApplicationTermination()
    }

    private func continueApplicationTermination() {
        if pendingPrint != nil {
            cancelPendingPrint()
        }
        guard hasUnsavedChanges else {
            finishTermination(allowing: true)
            return
        }
        pendingDocumentAction = .terminate
        NSApp?.activate(ignoringOtherApps: true)
    }

    func resolveUnsavedChanges(_ decision: UnsavedChangesDecision) {
        guard let action = pendingDocumentAction else { return }
        pendingDocumentAction = nil
        switch decision {
        case .discard:
            performDocumentAction(action)
        case .cancel:
            cancelDocumentAction(action)
        case .save:
            Task { [weak self] in
                await Task.yield()
                self?.saveBeforePerforming(action)
            }
        }
    }

    private func requestDocumentAction(_ action: PendingDocumentAction) {
        guard hasUnsavedChanges else {
            performDocumentAction(action)
            return
        }
        pendingDocumentAction = action
    }

    private func saveBeforePerforming(_ action: PendingDocumentAction) {
        if let currentDocumentURL {
            saveDocument(to: currentDocumentURL, continuingWith: action)
            return
        }
        FilePanelService.chooseSaveLocation(
            defaultName: document.name,
            isExportCopy: false
        ) { [weak self] url in
            guard let self else { return }
            guard let url else {
                cancelDocumentAction(action)
                return
            }
            saveDocument(to: url, continuingWith: action)
        }
    }

    private func performDocumentAction(_ action: PendingDocumentAction) {
        switch action {
        case .newDocument(let template):
            performNewDocument(template)
        case .open(let url):
            openDocument(from: url)
        case .terminate:
            finishTermination(allowing: true)
        }
    }

    private func cancelDocumentAction(_ action: PendingDocumentAction) {
        if action == .terminate {
            finishTermination(allowing: false)
        }
    }

    private func finishTermination(allowing termination: Bool) {
        let completion = terminationCompletion
        terminationCompletion = nil
        completion?(termination)
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

    func saveDocument(
        to url: URL,
        continuingWith action: PendingDocumentAction? = nil
    ) {
        let snapshot = document
        let files = documentFiles
        startDocumentOperation(
            failurePrefix: "保存失败",
            cancellingActionOnFailure: action
        ) {
            try await files.write(snapshot, to: url)
            return .saved(document: snapshot, url: url, continuingWith: action)
        }
    }

    func exportDocumentCopy(to url: URL) {
        let snapshot = document
        let files = documentFiles
        startDocumentOperation(failurePrefix: "导出失败") {
            try await files.write(snapshot, to: url)
            return .exported(url: url)
        }
    }

    func openDocument(from url: URL) {
        let files = documentFiles
        startDocumentOperation(failurePrefix: "打开失败") {
            .opened(document: try await files.readDocument(from: url), url: url)
        }
    }

    func importCSV(from url: URL) {
        let files = documentFiles
        startDocumentOperation(failurePrefix: "CSV 导入失败") {
            .importedCSV(try await files.readCSV(from: url))
        }
    }

    func importImage(from url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let files = documentFiles
        startDocumentOperation(failurePrefix: "导入图片失败") {
            .importedImage(
                try await files.readImage(from: url),
                name: name
            )
        }
    }

    private func startDocumentOperation(
        failurePrefix: String,
        cancellingActionOnFailure action: PendingDocumentAction? = nil,
        operation: @escaping @Sendable () async throws -> DocumentOperationResult
    ) {
        cancelDocumentOperation()
        autosaveTask?.cancel()
        let operationID = UUID()
        documentOperationID = operationID
        documentOperationTask = Task { [weak self] in
            do {
                let result = try await operation()
                guard let self else { return }
                guard !Task.isCancelled,
                      self.documentOperationID == operationID else {
                    if let action {
                        self.cancelDocumentAction(action)
                    }
                    self.finishDocumentOperation(id: operationID)
                    return
                }
                self.applyDocumentOperationResult(result)
                self.finishDocumentOperation(id: operationID)
            } catch is CancellationError {
                if let action {
                    self?.cancelDocumentAction(action)
                }
                self?.finishDocumentOperation(id: operationID)
            } catch {
                guard let self, self.documentOperationID == operationID else { return }
                self.printStatus = "\(failurePrefix)：\(error.localizedDescription)"
                if let action {
                    self.cancelDocumentAction(action)
                }
                self.finishDocumentOperation(id: operationID)
            }
        }
    }

    private func applyDocumentOperationResult(_ result: DocumentOperationResult) {
        switch result {
        case let .saved(snapshot, url, action):
            currentDocumentURL = url
            markSavedSnapshot(snapshot)
            printStatus = "已保存“\(url.lastPathComponent)”"
            if let action {
                if document == snapshot {
                    performDocumentAction(action)
                } else {
                    pendingDocumentAction = action
                }
            }
        case let .exported(url):
            printStatus = "已导出标签副本“\(url.lastPathComponent)”"
        case let .opened(opened, url):
            loadDocument(opened, from: url)
        case let .importedCSV(records):
            batchRecords = records
            printStatus = "已载入 \(records.count) 条批量数据"
        case let .importedImage(imported, name):
            addImageLayer(data: imported.data, name: name, aspectRatio: imported.aspectRatio)
        }
    }

    private func cancelDocumentOperation() {
        documentOperationID = nil
        documentOperationTask?.cancel()
        documentOperationTask = nil
    }

    private func finishDocumentOperation(id: UUID) {
        guard documentOperationID == id else { return }
        documentOperationID = nil
        documentOperationTask = nil
    }

    func waitForDocumentOperation() async {
        let task = documentOperationTask
        await task?.value
    }

    func loadDocument(_ document: LabelDocument, from url: URL) {
        autosaveTask?.cancel()
        LabelPreviewCache.shared.removeAll()
        replaceDocumentWithoutHistory(document)
        selectedLayerID = document.layers.last?.id
        selectedLayerIDs = Set(selectedLayerID.map { [$0] } ?? [])
        currentDocumentURL = url
        resetHistory()
        printStatus = "已打开标签“\(document.name)”。"
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
            throw DocumentFileError.invalidImage
        }
        addImageLayer(data: data, name: name, aspectRatio: aspectRatio)
    }

    private func addImageLayer(data: Data, name: String, aspectRatio: Double) {
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
        var layers = document.layers
        for index in layers.indices where targetIDs.contains(layers[index].id) {
            layers[index].isLocked = shouldLock
        }
        document.layers = layers
    }

    func undo() {
        guard let previous = history.undo(current: document) else { return }
        replaceDocumentWithoutHistory(previous)
        repairSelection()
        updateHistoryState()
        scheduleAutosave()
    }

    func redo() {
        guard let next = history.redo(current: document) else { return }
        replaceDocumentWithoutHistory(next)
        repairSelection()
        updateHistoryState()
        scheduleAutosave()
    }

    private func documentDidChange(from oldValue: LabelDocument) {
        guard !suppressHistory, oldValue != document else { return }
        history.recordChange(from: oldValue)
        canUndo = history.canUndo
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

    private func resetHistory() {
        history.reset(savedDocument: document)
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
        canUndo = history.canUndo
        canRedo = history.canRedo
        hasUnsavedChanges = history.isDirty(document)
    }

    private func markSavedSnapshot(_ snapshot: LabelDocument) {
        history.markSaved(snapshot)
        hasUnsavedChanges = history.isDirty(document)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard currentDocumentURL != nil else { return }
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let url = self.currentDocumentURL else { return }
            let snapshot = self.document
            do {
                try await self.documentFiles.write(snapshot, to: url)
                guard !Task.isCancelled, self.currentDocumentURL == url else { return }
                self.markSavedSnapshot(snapshot)
            } catch is CancellationError {
                return
            } catch {
                // Autosave is intentionally silent: an incidental disk error must not
                // replace printer faults or print progress in the shared status area.
            }
        }
    }

    func waitForAutosave() async {
        let task = autosaveTask
        await task?.value
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
        cancelPrintPreparation()
        pendingPrint = nil
        printStatus = "正在生成标签…"
        let document = document
        let settings = currentPrintJobSettings
        let name = printCopies == 1 ? document.name : "\(document.name) × \(printCopies)"
        let preparationID = UUID()
        printPreparationID = preparationID
        printPreparationTask = Task { [weak self] in
            do {
                let data = try await PrintJobBuilder.documentData(
                    document: document,
                    settings: settings
                )
                guard !Task.isCancelled,
                      let self,
                      self.printPreparationID == preparationID else { return }
                pendingPrint = .init(data: data, name: name, source: .document)
                printStatus = "标签已生成，等待确认"
                finishPrintPreparation(id: preparationID)
            } catch is CancellationError {
                self?.finishPrintPreparation(id: preparationID)
            } catch {
                guard let self, self.printPreparationID == preparationID else { return }
                pendingPrint = nil
                printStatus = error.localizedDescription
                finishPrintPreparation(id: preparationID)
            }
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

        cancelPrintPreparation()
        pendingPrint = nil
        printStatus = "正在生成 \(records.count) 张批量标签…"
        let document = document
        let settings = currentPrintJobSettings
        let preparationID = UUID()
        printPreparationID = preparationID
        printPreparationTask = Task { [weak self] in
            do {
                let data = try await PrintJobBuilder.batchData(
                    document: document,
                    records: records,
                    settings: settings
                )
                guard !Task.isCancelled,
                      let self,
                      self.printPreparationID == preparationID else { return }
                pendingPrint = .init(
                    data: data,
                    name: "批量标签 × \(records.count)",
                    source: .document
                )
                printStatus = "已生成 \(records.count) 张批量标签，等待确认"
                finishPrintPreparation(id: preparationID)
            } catch is CancellationError {
                self?.finishPrintPreparation(id: preparationID)
            } catch {
                guard let self, self.printPreparationID == preparationID else { return }
                pendingPrint = nil
                printStatus = error.localizedDescription
                finishPrintPreparation(id: preparationID)
            }
        }
    }

    private var currentPrintJobSettings: PrintJobSettings {
        PrintJobSettings(
            horizontalOffsetMM: calibrationOffsetX,
            verticalOffsetMM: calibrationOffsetY,
            copies: printCopies,
            inverted: printInverted,
            paperMode: paperMode,
            gapLengthMM: gapLengthMM,
            darkness: printDarkness,
            speed: printSpeed
        )
    }

    private func cancelPrintPreparation() {
        printPreparationID = nil
        printPreparationTask?.cancel()
        printPreparationTask = nil
    }

    private func finishPrintPreparation(id: UUID) {
        guard printPreparationID == id else { return }
        printPreparationID = nil
        printPreparationTask = nil
    }

    func waitForPrintPreparation() async {
        let task = printPreparationTask
        await task?.value
    }

    private func repeatedPrintData(for raster: P1Raster, copies: Int) -> Data {
        let settings = currentPrintJobSettings.withCopies(copies)
        return PrintJobBuilder.repeatedPrintData(for: raster, settings: settings)
    }

    func refreshUSBDevices() {
        usbDiscoveryTask?.cancel()
        let discoveryID = UUID()
        usbDiscoveryID = discoveryID
        usbDiscoveryTask = Task { [weak self] in
            let devices = await P1USBDiscovery.connectedDevicesAsync()
            guard !Task.isCancelled,
                  let self,
                  self.usbDiscoveryID == discoveryID else { return }
            self.applyDiscoveredUSBDevices(devices)
            self.usbDiscoveryID = nil
            self.usbDiscoveryTask = nil
            if !devices.isEmpty {
                self.refreshPrinterStatus()
            }
        }
    }

    private func applyDiscoveredUSBDevices(_ devices: [P1USBDevice]) {
        usbDevices = devices
        guard !devices.isEmpty else {
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
            let devices = await P1USBDiscovery.connectedDevicesAsync()
            guard !Task.isCancelled else { return }
            applyDiscoveredUSBDevices(devices)
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
        guard !usbDevices.isEmpty, !isVerifyingUSB, !isSendingPrint else { return }
        isVerifyingUSB = true
        printStatus = "正在验证 USB 打印通道…"
        Task {
            defer { isVerifyingUSB = false }
            do {
                try await usbTransport.probe()
                printStatus = "已验证 P1 USB 打印接口。"
            } catch {
                printStatus = "已检测到 P1；\(error.localizedDescription)"
            }
        }
    }

    func refreshPrinterStatus() {
        guard !isSendingPrint else { return }
        printerStatusTask?.cancel()
        if bluetoothPrinter.isConnected {
            printerStatusTask = Task {
                do {
                    let status = try await bluetoothPrinter.requestPrinterStatus() ?? .unknown
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
        let selectedIDs = effectiveSelectedLayerIDs
        var layers = document.layers
        var changed = false
        for index in layers.indices
        where selectedIDs.contains(layers[index].id) && !layers[index].isLocked {
            let original = layers[index]
            layers[index].x = min(
                max(0, layers[index].x + dx),
                max(0, document.paper.widthMM - layers[index].width)
            )
            layers[index].y = min(
                max(0, layers[index].y + dy),
                max(0, document.paper.heightMM - layers[index].height)
            )
            changed = changed || layers[index] != original
        }
        if changed {
            document.layers = layers
        }
    }

    func alignSelection(_ alignment: LayerAlignment) {
        let selectedIDs = effectiveSelectedLayerIDs
        var layers = document.layers
        var changed = false
        let indices = layers.indices.filter {
            selectedIDs.contains(layers[$0].id) && !layers[$0].isLocked
        }
        guard !indices.isEmpty else { return }
        let minX = indices.map { layers[$0].x }.min() ?? 0
        let maxX = indices.map { layers[$0].x + layers[$0].width }.max() ?? document.paper.widthMM
        let minY = indices.map { layers[$0].y }.min() ?? 0
        let maxY = indices.map { layers[$0].y + layers[$0].height }.max() ?? document.paper.heightMM

        for index in indices {
            let original = layers[index]
            switch alignment {
            case .left:
                layers[index].x = indices.count == 1 ? 0 : minX
            case .horizontalCenter:
                let center = indices.count == 1 ? document.paper.widthMM / 2 : (minX + maxX) / 2
                layers[index].x = center - layers[index].width / 2
            case .right:
                let edge = indices.count == 1 ? document.paper.widthMM : maxX
                layers[index].x = edge - layers[index].width
            case .top:
                layers[index].y = indices.count == 1 ? 0 : minY
            case .verticalCenter:
                let center = indices.count == 1 ? document.paper.heightMM / 2 : (minY + maxY) / 2
                layers[index].y = center - layers[index].height / 2
            case .bottom:
                let edge = indices.count == 1 ? document.paper.heightMM : maxY
                layers[index].y = edge - layers[index].height
            }
            changed = changed || layers[index] != original
        }
        if changed {
            document.layers = layers
        }
    }

    func confirmPendingPrint() {
        guard let pendingPrint, !isSendingPrint else { return }
        self.pendingPrint = nil
        let connectionName = activePrintConnectionName
        let historyID = printHistory.begin(pendingPrint, connection: connectionName)
        activePrintHistoryID = historyID
        let precedingStatusTask = printerStatusTask
        printerStatusTask?.cancel()
        printerStatusTask = nil
        isSendingPrint = true
        printSendingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isSendingPrint = false
                printSendingTask = nil
                if activePrintHistoryID == historyID {
                    activePrintHistoryID = nil
                }
            }
            do {
                await precedingStatusTask?.value
                try Task.checkCancellation()
                if bluetoothPrinter.isConnected {
                    if let status = try await bluetoothPrinter.requestPrinterStatus(),
                       !status.isReady {
                        deviceStatus = status
                        printStatus = "\(status.title)：\(status.detail)"
                        self.pendingPrint = pendingPrint
                        printHistory.markFailed(historyID, message: printStatus)
                        return
                    }
                    try await bluetoothPrinter.send(pendingPrint.data)
                    try Task.checkCancellation()
                    printHistory.markSucceeded(historyID)
                    showPrintCompletedStatus(
                        "“\(pendingPrint.name)”已通过\(activePrintConnectionName)发送 \(bluetoothPrinter.lastTransferByteCount) 字节"
                    )
                    try? await Task.sleep(for: .milliseconds(500))
                    if let status = try? await bluetoothPrinter.requestPrinterStatus() {
                        deviceStatus = status
                        if !status.isReady {
                            printStatus = "\(status.title)：\(status.detail)"
                        }
                    }
                } else {
                    try await usbTransport.send(pendingPrint.data)
                    try Task.checkCancellation()
                    printHistory.markSucceeded(historyID)
                    showPrintCompletedStatus(
                        "“\(pendingPrint.name)”已通过\(activePrintConnectionName)发送"
                    )
                }
            } catch is CancellationError {
                printHistory.markCancelled(historyID, detail: "用户取消了任务")
                printStatus = "已取消打印任务"
            } catch {
                printStatus = error.localizedDescription
                self.pendingPrint = pendingPrint
                printHistory.markFailed(historyID, message: error.localizedDescription)
            }
        }
    }

    func waitForPrintSending() async {
        let task = printSendingTask
        await task?.value
    }

    func cancelPendingPrint() {
        let wasPreparing = printPreparationID != nil
        cancelPrintPreparation()
        guard pendingPrint != nil || wasPreparing else { return }
        pendingPrint = nil
        printStatus = "已取消打印"
    }

    func retryPrint(_ historyID: UUID) {
        guard !isSendingPrint else {
            printStatus = "当前打印任务完成后才能重试"
            return
        }
        guard let job = printHistory.retryJob(historyID) else {
            printStatus = "此历史任务的打印数据已释放，请重新生成标签"
            return
        }
        pendingPrint = PendingPrint(data: job.data, name: job.name, source: .history)
        printStatus = "“\(job.name)”已准备重新打印，等待确认"
    }

    func cancelPrintJob(_ historyID: UUID) {
        guard activePrintHistoryID == historyID else { return }
        printHistory.markCancelled(historyID, detail: "用户请求取消")
        printSendingTask?.cancel()
        bluetoothPrinter.cancelCurrentTransfer()
        printStatus = bluetoothPrinter.isConnected
            ? "正在取消蓝牙打印任务"
            : "已请求取消；USB 数据若已发送到设备则无法撤回"
    }

    func requestExportDiagnosticReport() {
        FilePanelService.chooseDiagnosticReportLocation { [weak self] url in
            guard let self, let url else { return }
            exportDiagnosticReport(to: url)
        }
    }

    func exportDiagnosticReport(to url: URL) {
        diagnosticExportTask?.cancel()
        let snapshot = DiagnosticSnapshot(
            generatedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.runtimeArchitecture,
            connectionKind: bluetoothPrinter.isConnected ? "蓝牙" : (usbDevices.isEmpty ? "未连接" : "USB"),
            usbDeviceCount: usbDevices.count,
            bluetoothState: bluetoothPrinter.isConnected ? "已连接" : "未连接",
            deviceStatus: deviceStatus,
            recentPrintStates: Array(printHistory.entries.prefix(20).map(\.status))
        )
        diagnosticExportTask = Task { [weak self] in
            do {
                try await DiagnosticReportService.write(snapshot, to: url)
                guard !Task.isCancelled else { return }
                self?.printStatus = "已导出脱敏诊断报告“\(url.lastPathComponent)”"
            } catch is CancellationError {
                return
            } catch {
                self?.printStatus = "诊断报告导出失败：\(error.localizedDescription)"
            }
        }
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

    func waitForPrintStatusReset() async {
        let task = printCompletionResetTask
        await task?.value
    }

    static func normalizedPrinterStatus(_ status: String) -> String {
        PrinterStatusText.normalize(status)
    }

    private static func normalizedCalibrationOffset(_ value: Double) -> Double {
        P1PrintGeometry.normalizedOffsetMM(value)
    }

    private static var runtimeArchitecture: String {
        #if arch(arm64)
        "Apple Silicon (arm64)"
        #else
        "未知架构"
        #endif
    }
}

private extension NSPasteboard.PasteboardType {
    static let p1LabelLayers = NSPasteboard.PasteboardType("com.louis.p1label.layers")
}

private enum DocumentOperationResult: Sendable {
    case saved(
        document: LabelDocument,
        url: URL,
        continuingWith: PendingDocumentAction?
    )
    case exported(url: URL)
    case opened(document: LabelDocument, url: URL)
    case importedCSV([[String: String]])
    case importedImage(DocumentFileService.ImportedImage, name: String)
}
