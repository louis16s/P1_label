import SwiftUI

struct MainToolbar: ToolbarContent {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: AppModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            EditableLabelTitle(model: model)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu("添加", systemImage: "plus") {
                Button("文字", systemImage: "textformat") {
                    model.addTextLayer()
                }
                Button("图片…", systemImage: "photo") {
                    model.requestImportImage()
                }
                Divider()
                Button("二维码", systemImage: "qrcode") {
                    model.addShapeLayer(.qrCode)
                }
                Button("Code 128 条码", systemImage: "barcode") {
                    model.addShapeLayer(.barcode)
                }
                Button("矩形", systemImage: "rectangle") {
                    model.addShapeLayer(.rectangle)
                }
                Button("圆形", systemImage: "circle") {
                    model.addShapeLayer(.ellipse)
                }
                Button("直线", systemImage: "line.diagonal") {
                    model.addShapeLayer(.line)
                }
            }
            Menu("文件", systemImage: "doc") {
                Button("保存", systemImage: "square.and.arrow.down") {
                    model.requestSave()
                }
                Button("另存为…", systemImage: "doc.badge.plus") {
                    model.requestSaveAs()
                }
                Divider()
                Button("导入标签…", systemImage: "square.and.arrow.down.on.square") {
                    model.requestOpenDocument()
                }
                Button("导入 CSV 批量数据…", systemImage: "tablecells") {
                    model.requestImportCSV()
                }
                Button("导出副本…", systemImage: "square.and.arrow.up") {
                    model.requestExportCopy()
                }
            }
            Button("打印机设置", systemImage: "gearshape") {
                openWindow(id: "printer")
            }
            Button("打印标签", systemImage: "printer") {
                model.prepareDocumentPrint()
            }
        }
    }
}

private struct EditableLabelTitle: View {
    @Bindable var model: AppModel
    @State private var isEditing = false
    @State private var originalName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("标签名称", text: $model.document.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                    .frame(width: 420)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .onExitCommand { cancel() }
            } else {
                Button(action: beginEditing) {
                    Text(model.document.name + (model.hasUnsavedChanges ? " — 已编辑" : ""))
                        .font(.headline)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("单击或双击修改标签名称")
                .accessibilityHint("单击或双击修改标签名称")
            }
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused, isEditing {
                commit()
            }
        }
    }

    private func beginEditing() {
        originalName = model.document.name
        isEditing = true
        DispatchQueue.main.async { isFocused = true }
    }

    private func commit() {
        guard isEditing else { return }
        let cleaned = model.document.name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.document.name = cleaned.isEmpty ? "未命名标签" : cleaned
        isEditing = false
        isFocused = false
    }

    private func cancel() {
        guard isEditing else { return }
        model.document.name = originalName
        isEditing = false
        isFocused = false
    }
}
