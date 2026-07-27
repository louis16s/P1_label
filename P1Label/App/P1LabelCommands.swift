import SwiftUI

struct P1LabelCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 P1 Label") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .newItem) {
            Button("新建标签") { model.newDocument() }
                .keyboardShortcut("n")
            Button("打开标签…") { model.requestOpenDocument() }
                .keyboardShortcut("o")
            Divider()
            Button("导入图片…") { model.requestImportImage() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("导入 CSV 批量数据…") { model.requestImportCSV() }
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") { model.requestSave() }
                .keyboardShortcut("s")
            Button("另存为…") { model.requestSaveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("导出标签副本…") { model.requestExportCopy() }
        }

        CommandGroup(replacing: .printItem) {
            Button("打印当前标签…") { model.prepareDocumentPrint() }
                .keyboardShortcut("p")
                .disabled(model.document.layers.isEmpty)
            Button("批量打印标签…") { model.prepareBatchPrint() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(model.document.layers.isEmpty)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("撤销") { model.undo() }
                .keyboardShortcut("z")
                .disabled(!model.canUndo)
            Button("重做") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("剪切") { model.cutSelectedLayers() }
                .keyboardShortcut("x")
                .disabled(!model.hasSelection || model.selectedLayerIsLocked)
            Button("拷贝") { model.copySelectedLayers() }
                .keyboardShortcut("c")
                .disabled(!model.hasSelection)
            Button("粘贴") { model.pasteSelectedLayers() }
                .keyboardShortcut("v")
            Divider()
            Button("制作副本") { model.duplicateSelectedLayer() }
                .keyboardShortcut("d")
                .disabled(!model.hasSelection)
            Button("删除") { model.deleteSelectedLayer() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!model.hasSelection || model.selectedLayerIsLocked)
            Divider()
            Button("全选") { model.selectAllLayers() }
                .keyboardShortcut("a")
                .disabled(model.document.layers.isEmpty)
            Button("取消选择") { model.clearLayerSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!model.hasSelection)
        }

        CommandMenu("插入") {
            Button("文字") { model.addTextLayer() }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button("图片…") { model.requestImportImage() }
            Divider()
            Button("二维码") { model.addShapeLayer(.qrCode) }
            Button("Code 128 条码") { model.addShapeLayer(.barcode) }
            Divider()
            Button("矩形") { model.addShapeLayer(.rectangle) }
            Button("圆形") { model.addShapeLayer(.ellipse) }
            Button("直线") { model.addShapeLayer(.line) }
        }

        CommandMenu("排列") {
            Button(model.selectedLayerIsLocked ? "解锁所选元素" : "锁定所选元素") {
                model.toggleSelectedLayersLocked()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(!model.hasSelection)
            Divider()
            alignmentButton("左对齐", .left)
            alignmentButton("水平居中", .horizontalCenter)
            alignmentButton("右对齐", .right)
            Divider()
            alignmentButton("顶端对齐", .top)
            alignmentButton("垂直居中", .verticalCenter)
            alignmentButton("底端对齐", .bottom)
        }

        CommandMenu("打印机") {
            Button("打印机设置…") { openWindow(id: "printer") }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            Divider()
            Button("刷新 USB 连接") { model.refreshUSBDevices() }
            Button("扫描蓝牙打印机") { model.bluetoothDiscovery.startScan() }
            Button("读取打印机状态") { model.refreshPrinterStatus() }
                .disabled(!model.hasConnectedPrinter)
            Divider()
            Button("校准标签间隙…") {
                openWindow(id: "printer")
                model.preparePaperCalibration()
            }
            .disabled(!model.hasConnectedPrinter)
            Button("打印校准页…") {
                openWindow(id: "printer")
                model.prepareTestPrint()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!model.hasConnectedPrinter)
        }

        CommandGroup(replacing: .help) {
            Button("P1 Label 使用说明") {
                openURL("https://github.com/louis16s/P1_label#readme")
            }
            Button("SDK 功能支持情况") { openWindow(id: "sdk-support") }
            Divider()
            Button("检查更新…") { openWindow(id: "about") }
            Button("在 GitHub 查看 P1 Label") {
                openURL("https://github.com/louis16s/P1_label")
            }
        }
    }

    private func alignmentButton(_ title: String, _ alignment: LayerAlignment) -> some View {
        Button(title) { model.alignSelection(alignment) }
            .disabled(!model.canAlignSelection)
    }

    private func openURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
