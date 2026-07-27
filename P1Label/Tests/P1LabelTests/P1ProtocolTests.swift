import Foundation
import AppKit
import Testing
@testable import P1Label

struct P1ProtocolTests {
    @Test func photoCalibrationComputesOppositeCorrection() throws {
        let result = try PhotoCalibrationAnalyzer.correction(
            paper: .init(
                topLeft: CGPoint(x: 0, y: 1),
                topRight: CGPoint(x: 1, y: 1),
                bottomRight: CGPoint(x: 1, y: 0),
                bottomLeft: CGPoint(x: 0, y: 0)
            ),
            printedFrame: .init(
                topLeft: CGPoint(x: 1.5 / 40, y: 1 - 1.5 / 30),
                topRight: CGPoint(x: 39.5 / 40, y: 1 - 1.5 / 30),
                bottomRight: CGPoint(x: 39.5 / 40, y: 1 - 29.5 / 30),
                bottomLeft: CGPoint(x: 1.5 / 40, y: 1 - 29.5 / 30)
            ),
            paperSize: PaperSize(widthMM: 40, heightMM: 30)
        )
        #expect(abs(result.horizontalOffsetMM + 0.5) < 0.001)
        #expect(abs(result.verticalOffsetMM + 0.5) < 0.001)
        #expect(abs(result.rotationDegrees) < 0.001)
    }

    @Test func blankDocumentStartsWithoutObjects() {
        #expect(LabelDocument.blank.layers.isEmpty)
    }

    @Test func csvParserSupportsQuotedFieldsAndSequenceColumn() throws {
        let csv = Data("姓名,备注\n小王,\"A, B\"\n小李,第二行\n".utf8)
        let records = try CSVBatchParser.records(from: csv)
        #expect(records.count == 2)
        #expect(records[0]["姓名"] == "小王")
        #expect(records[0]["备注"] == "A, B")
        #expect(records[1]["序号"] == "2")
    }

    @Test func usbPrinterPortStatusDecodesStandardBits() {
        let ready = P1PrinterPortStatus(rawValue: 0x18)
        #expect(ready.isSelected)
        #expect(!ready.isPaperEmpty)
        #expect(!ready.hasError)
        #expect(ready.displayName == "就绪")

        let empty = P1PrinterPortStatus(rawValue: 0x38)
        #expect(empty.isPaperEmpty)
        #expect(empty.displayName == "缺纸")
    }

    @Test func oneHundredTenPercentFitsWithoutScrollbars() {
        let paper = PaperSize(widthMM: 40, heightMM: 30)
        for viewport in [
            CGSize(width: 620, height: 480),
            CGSize(width: 689, height: 550),
            CGSize(width: 900, height: 700)
        ] {
            let fit = CanvasLayout.fitScale(viewport: viewport, paper: paper)
            let scaleAt110Percent = fit * CanvasLayout.noScrollZoom
            let content = CanvasLayout.contentSize(
                viewport: viewport,
                paper: paper,
                scale: scaleAt110Percent
            )
            #expect(content.width == viewport.width)
            #expect(content.height == viewport.height)
        }
    }

    @Test func serializesConfirmedSetupCommands() {
        #expect(P1Protocol.setPrintWidth() == Data([0x1F, 0x27, 0x01, 0x30, 0x88]))
        #expect(P1Protocol.setGapType(.gap) == Data([0x1F, 0x42, 0x01, 0x02, 0x88]))
        #expect(P1Protocol.setGapType(.blackMark) == Data([0x1F, 0x42, 0x01, 0x03, 0x88]))
        #expect(P1Protocol.setPageHeight(dots: 240) == Data([0x1F, 0x26, 0x02, 0xC0, 0xF0, 0x88]))
        #expect(P1Protocol.setGapLength(millimeters: 2) == Data([0x1F, 0x45, 0x01, 0x02, 0x88]))
        #expect(P1Protocol.setDarkness(6) == Data([0x1F, 0x43, 0x01, 0x05, 0x88]))
        #expect(P1Protocol.setSpeed(3) == Data([0x1F, 0x44, 0x01, 0x02, 0x88]))
    }

    @Test func officialPageJobUsesFramingAndAvoidsLegacyBoundaryCommand() {
        let raster = P1Raster(width: P1Protocol.printWidthBytes * 8, height: 1)
        let job = P1Protocol.printJob(
            raster: raster,
            paperMode: .gap,
            gapLengthMM: 2,
            darkness: 6,
            speed: 3
        )
        #expect(job.starts(with: P1Protocol.pageStart))
        #expect(job.suffix(P1Protocol.pageEnd.count) == P1Protocol.pageEnd)
        #expect(job.starts(with: P1Protocol.pageStart))
    }

    @Test func serializesRowsWithLittleEndianBitCount() {
        let command = P1Protocol.printRow(Data([0x80, 0x00]))
        #expect(command == Data([0x1F, 0x2A, 0x10, 0x00, 0x80, 0x00]))
    }

    @MainActor
    @Test func canvasInputDistinguishesClicksAndMovesWithArrowKeys() throws {
        let view = CanvasLayerInputCapture.KeyView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        var singleClicks = 0
        var doubleClicks = 0
        var movements: [(Double, Double)] = []
        view.onSingleClick = { _ in singleClicks += 1 }
        view.onDoubleClick = { doubleClicks += 1 }
        view.onMove = { movements.append(($0, $1)) }

        let singleClick = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let doubleClick = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 2,
            pressure: 1
        ))
        view.mouseDown(with: singleClick)
        view.mouseDown(with: doubleClick)

        for keyCode in [UInt16(123), 124, 125, 126] {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            ))
            view.keyDown(with: event)
        }

        #expect(singleClicks == 1)
        #expect(doubleClicks == 1)
        #expect(movements.map(\.0) == [-0.1, 0.1, 0, 0])
        #expect(movements.map(\.1) == [0, 0, 0.1, -0.1])
    }

    @MainActor
    @Test func canvasDragUsesStableWindowCoordinatesWhileLayerMoves() throws {
        let view = CanvasLayerInputCapture.KeyView(
            frame: NSRect(x: 10, y: 10, width: 100, height: 30)
        )
        var translations: [CGSize] = []
        view.onSingleClick = { _ in }
        view.onDrag = { translations.append($0) }

        let mouseDown = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 50, y: 50),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        view.mouseDown(with: mouseDown)

        // SwiftUI repositions the capture view as the model changes.
        view.frame.origin = NSPoint(x: 30, y: 10)
        let mouseDragged = try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: NSPoint(x: 70, y: 40),
            modifierFlags: [],
            timestamp: 0.1,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        ))
        view.mouseDragged(with: mouseDragged)

        #expect(translations == [CGSize(width: 20, height: 10)])
    }

    @Test func packsBlackDotsMostSignificantBitFirst() {
        var raster = P1Raster(width: 8, height: 1)
        raster[0, 0] = true
        raster[7, 0] = true
        #expect(raster.packedRows() == [Data([0x81])])
    }

    @Test func offsetsRasterAndCropsAtPaperEdge() {
        var raster = P1Raster(width: 8, height: 2)
        raster[0, 0] = true
        raster[7, 1] = true
        let shifted = raster.offsetBy(x: 1, y: 0)
        #expect(shifted[1, 0])
        #expect(!shifted[7, 1])
    }

    @Test func rendersNativeDocumentAtP1Resolution() throws {
        let document = LabelDocument(
            name: "测试",
            paper: PaperSize(widthMM: 40, heightMM: 20),
            layers: [.shape(.rectangle, x: 2, y: 2)]
        )
        let raster = try LabelRasterizer.raster(
            document: document,
            horizontalOffsetMM: 1,
            verticalOffsetMM: 0
        )
        #expect(raster.width == 384)
        #expect(raster.height == 160)
        #expect(raster.dots.contains(true))
    }

    @Test func labelBackupRoundTripsAllLayerData() throws {
        var document = LabelDocument.example
        document.layers.append(.image(Data([0x01, 0x02, 0x03]), name: "测试图片", x: 3, y: 4))
        document.layers[0].fontName = "PingFang SC"
        document.layers[0].isItalic = true
        document.layers[0].isUnderline = true
        document.layers[0].isStrikethrough = true
        document.layers[0].textAlignment = .center
        document.layers[0].isLocked = true
        let imageIndex = document.layers.index(before: document.layers.endIndex)
        document.layers[imageIndex].imageThreshold = 0.4
        document.layers[imageIndex].imageAlgorithm = .atkinson
        document.layers[imageIndex].imagePreviewMode = .color
        document.layers[imageIndex].imageScaleMode = .fill
        let data = try JSONEncoder().encode(document)
        let restored = try JSONDecoder().decode(LabelDocument.self, from: data)
        #expect(restored == document)
        #expect(restored.layers.last?.imageData == Data([0x01, 0x02, 0x03]))
    }

    @MainActor
    @Test func lockedObjectCannotBeNudged() {
        let model = AppModel()
        var layer = LabelLayer.text("锁定", x: 4, y: 4, fontSizeMM: 3)
        layer.isLocked = true
        model.document.layers = [layer]
        model.selectedLayerID = layer.id
        model.nudgeSelectedLayer(dx: 1, dy: 1)
        #expect(model.document.layers[0].x == 4)
        #expect(model.document.layers[0].y == 4)

        model.document.layers[0].isLocked = false
        model.nudgeSelectedLayer(dx: 1, dy: 1)
        #expect(model.document.layers[0].x == 5)
        #expect(model.document.layers[0].y == 5)
    }

    @MainActor
    @Test func lockedObjectCannotBeDeleted() {
        let model = AppModel()
        var layer = LabelLayer.text("锁定", x: 4, y: 4, fontSizeMM: 3)
        layer.isLocked = true
        model.document.layers = [layer]
        model.selectedLayerID = layer.id
        model.deleteSelectedLayer()
        #expect(model.document.layers.count == 1)
        #expect(model.selectedLayerIsLocked)
    }

    @MainActor
    @Test func printOffsetsPersistAcrossModelRelaunch() throws {
        let suiteName = "P1LabelTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let firstModel = AppModel(preferences: preferences)
        firstModel.calibrationOffsetX = -1.3
        firstModel.calibrationOffsetY = 2.7
        firstModel.gapLengthMM = 3
        firstModel.printDarkness = 10
        firstModel.printSpeed = 3
        firstModel.printCopies = 4

        let relaunchedModel = AppModel(preferences: preferences)
        #expect(relaunchedModel.calibrationOffsetX == -1.3)
        #expect(relaunchedModel.calibrationOffsetY == 2.7)
        #expect(relaunchedModel.gapLengthMM == 3)
        #expect(relaunchedModel.printDarkness == 10)
        #expect(relaunchedModel.printSpeed == 3)
        #expect(relaunchedModel.printCopies == 4)
    }

    @Test func defaultTextBoxHeightMatchesFontHeight() {
        let layer = LabelLayer.text("文字", x: 0, y: 0, fontSizeMM: 3.5)
        #expect(layer.height == 3.5)
    }

    @Test func sdkDeviceStatusMapsPaperCoverAndHeatErrors() {
        #expect(P1DeviceStatus.sdk(code: 0x35).title == "打印机缺纸")
        #expect(P1DeviceStatus.sdk(code: 0x34).title == "纸仓盖已打开")
        #expect(P1DeviceStatus.sdk(code: 0x33).title == "打印头过热")
        #expect(P1DeviceStatus.sdk(code: 0).isReady)
    }

    @Test func rasterCanBeInvertedForSdkAntiColorEquivalent() {
        var raster = P1Raster(width: 8, height: 1)
        raster[0, 0] = true
        let inverted = raster.inverted()
        #expect(!inverted[0, 0])
        #expect(inverted[1, 0])
        #expect(inverted.packedRows() == [Data([0x7F])])
    }

    @Test func positioningCalibrationSheetUsesPaperEdgesAndAsymmetricMarkers() {
        let raster = P1Raster.positioningCalibrationSheet(
            width: 384,
            paperWidth: 320,
            height: 240
        )

        // A 40 mm label is right-aligned on the 48 mm print head.
        for y in 0..<raster.height {
            for x in 0..<64 {
                #expect(!raster[x, y])
            }
        }
        #expect(raster[72, 8]) // one-millimeter inset border
        #expect(raster[376 - 1, 8])
        #expect(raster[224, 120]) // center cross

        // Top-left and top-right IDs deliberately differ.
        #expect(raster[84, 20])
        #expect(!raster[88, 20])
        #expect(raster[352, 20])
        #expect(raster[356, 20])
    }

    @MainActor
    @Test func automaticPrinterDiscoveryStopsAtItsDeadline() async {
        let model = AppModel()
        await model.discoverPrinterAutomatically(
            interval: .milliseconds(5),
            maximumDuration: .milliseconds(20)
        )
        // A second run must be allowed after the first run completes.
        await model.discoverPrinterAutomatically(
            interval: .milliseconds(1),
            maximumDuration: .milliseconds(2)
        )
    }

    @MainActor
    @Test func editorPreviewCacheReusesExpensiveGeneratedImages() throws {
        let firstQR = try #require(LabelPreviewCache.shared.qrCode("P1 Label"))
        let secondQR = try #require(LabelPreviewCache.shared.qrCode("P1 Label"))
        #expect(firstQR === secondQR)

        let firstBarcode = try #require(LabelPreviewCache.shared.barcode("P1-0001"))
        let secondBarcode = try #require(LabelPreviewCache.shared.barcode("P1-0001"))
        #expect(firstBarcode === secondBarcode)
    }

    @MainActor
    @Test func imageImportValidatesAndKeepsSourceAspectRatio() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let model = AppModel()
        try model.addImageLayer(data: png, name: "测试图片")
        let image = try #require(model.document.layers.first)
        #expect(image.kind == .image)
        #expect(image.width > image.height)
        #expect(image.imageData == png)
        #expect(image.imagePreviewMode == .color)
    }

    @Test func imageAlgorithmsProduceValidDistinctPrintPreviews() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 8,
            pixelsHigh: 8,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        for y in 0..<8 {
            for x in 0..<8 {
                let value = CGFloat(x + y) / 14
                bitmap.setColor(
                    NSColor(calibratedRed: value, green: 1 - value, blue: 0.35, alpha: 1),
                    atX: x,
                    y: y
                )
            }
        }
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        var outputs = Set<Data>()
        for algorithm in LabelImageAlgorithm.allCases {
            let image = try #require(LabelImageProcessor.processedImage(
                data: png,
                width: 32,
                height: 32,
                threshold: 0.62,
                algorithm: algorithm,
                scaleMode: .fill
            ))
            let providerData = try #require(image.dataProvider?.data)
            outputs.insert(providerData as Data)
        }
        #expect(outputs.count >= 3)

        let color = try #require(LabelImageProcessor.previewImage(
            data: png,
            width: 32,
            height: 32,
            previewMode: .color,
            threshold: 0.62,
            algorithm: .floydSteinberg,
            scaleMode: .fill
        ))
        let grayscale = try #require(LabelImageProcessor.previewImage(
            data: png,
            width: 32,
            height: 32,
            previewMode: .grayscale,
            threshold: 0.62,
            algorithm: .floydSteinberg,
            scaleMode: .fill
        ))
        #expect((color.dataProvider?.data as Data?) != (grayscale.dataProvider?.data as Data?))
    }

    @MainActor
    @Test func fileWorkflowsSaveOpenExportAndImportRealFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("P1LabelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let savedURL = directory.appendingPathComponent("主标签.p1label.json")
        let model = AppModel()
        model.document.name = "可编辑标题"
        model.addTextLayer()
        #expect(model.saveDocument(to: savedURL))
        #expect(FileManager.default.fileExists(atPath: savedURL.path))
        #expect(model.currentDocumentURL == savedURL)
        #expect(!model.hasUnsavedChanges)

        let reopened = AppModel()
        #expect(reopened.openDocument(from: savedURL))
        #expect(reopened.document.name == "可编辑标题")
        #expect(reopened.document.layers.count == 1)
        #expect(reopened.currentDocumentURL == savedURL)

        let exportedURL = directory.appendingPathComponent("导出副本.p1label.json")
        let exportOnlyModel = AppModel()
        exportOnlyModel.document.name = "副本"
        #expect(exportOnlyModel.exportDocumentCopy(to: exportedURL))
        #expect(FileManager.default.fileExists(atPath: exportedURL.path))
        #expect(exportOnlyModel.currentDocumentURL == nil)

        let csvURL = directory.appendingPathComponent("批量.csv")
        try Data("姓名,编号\n小王,001\n小李,002\n".utf8).write(to: csvURL)
        #expect(reopened.importCSV(from: csvURL))
        #expect(reopened.batchRecords.count == 2)
        #expect(reopened.batchRecords[0]["姓名"] == "小王")

        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 3,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let imageURL = directory.appendingPathComponent("图片.png")
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: imageURL)
        #expect(reopened.importImage(from: imageURL))
        #expect(reopened.document.layers.last?.kind == .image)

        #expect(!reopened.openDocument(from: csvURL))
        #expect(reopened.printStatus.contains("打开失败"))
    }

    @MainActor
    @Test func printConfirmationOnlyMentionsNonZeroOffsets() throws {
        let suiteName = "P1LabelTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = AppModel(preferences: preferences)

        model.calibrationOffsetX = 0
        model.calibrationOffsetY = 0
        #expect(!model.hasNonZeroPrintOffset)
        #expect(!model.documentPrintConfirmationMessage.contains("打印偏移"))

        model.calibrationOffsetX = -1.2
        #expect(model.hasNonZeroPrintOffset)
        #expect(model.documentPrintConfirmationMessage.contains("打印偏移"))
        #expect(model.documentPrintConfirmationMessage.contains("左右 -1.2 mm"))
    }

    @MainActor
    @Test func multiSelectionAlignsAndMovesTogether() {
        let model = AppModel()
        let first = LabelLayer.text("A", x: 2, y: 2, fontSizeMM: 3)
        let second = LabelLayer.text("B", x: 10, y: 8, fontSizeMM: 3)
        model.document.layers = [first, second]
        model.selectedLayerID = second.id
        model.selectedLayerIDs = [first.id, second.id]

        model.alignSelection(.left)
        #expect(model.document.layers[0].x == 2)
        #expect(model.document.layers[1].x == 2)
        model.nudgeSelectedLayer(dx: 1, dy: 1)
        #expect(model.document.layers[0].x == 3)
        #expect(model.document.layers[1].x == 3)
        #expect(model.document.layers[0].y == 3)
        #expect(model.document.layers[1].y == 9)
    }

    @MainActor
    @Test func documentHistoryTracksUndoRedoAndDirtyState() {
        let model = AppModel()
        #expect(!model.hasUnsavedChanges)
        model.addTextLayer()
        #expect(model.canUndo)
        #expect(model.hasUnsavedChanges)
        #expect(model.document.layers.count == 1)

        model.undo()
        #expect(model.document.layers.isEmpty)
        #expect(model.canRedo)
        #expect(!model.hasUnsavedChanges)

        model.redo()
        #expect(model.document.layers.count == 1)
        #expect(model.hasUnsavedChanges)
    }

    @Test func alignsNarrowLabelToRightSideOfPrintHead() throws {
        let document = LabelDocument(
            name: "右对齐",
            paper: PaperSize(widthMM: 40, heightMM: 20),
            layers: [.shape(.rectangle, x: 0, y: 2)]
        )
        let raster = try LabelRasterizer.raster(
            document: document,
            horizontalOffsetMM: 0,
            verticalOffsetMM: 0
        )
        let firstPrintedColumn = (0..<raster.width).first { x in
            (0..<raster.height).contains { y in raster[x, y] }
        }
        // The 2 px outline is centered on the 64 px right-alignment origin,
        // so antialiasing may touch the immediately preceding column.
        #expect((63...64).contains(firstPrintedColumn ?? -1))
    }
}
