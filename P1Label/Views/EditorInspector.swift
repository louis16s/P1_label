import AppKit
import SwiftUI

struct EditorInspector: View {
    @Bindable var model: AppModel
    @AppStorage("nudgeStep") private var nudgeStep = 0.1
    @AppStorage("snapToGrid") private var snapToGrid = true
    @State private var isPrintOffsetExpanded = false
    @State private var isBatchExpanded = false

    var body: some View {
        Form {
            if let index = selectedIndex {
                Section("元素") {
                    LabeledContent("名称", value: model.document.layers[index].name)
                    if model.selectedLayerIDs.count > 1 {
                        LabeledContent("多选", value: "\(model.selectedLayerIDs.count) 个元素")
                    }
                    Toggle("锁定元素", isOn: $model.document.layers[index].isLocked)
                    if model.document.layers[index].isLocked {
                        Text("锁定后不能移动或编辑；双击画布右下角的锁可解锁。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TextContentSection(layer: $model.document.layers[index])
                    .disabled(model.document.layers[index].isLocked)

                Section("位置") {
                    HStack {
                        TextField("X (mm)", value: $model.document.layers[index].x, format: .number.precision(.fractionLength(1)))
                        TextField("Y (mm)", value: $model.document.layers[index].y, format: .number.precision(.fractionLength(1)))
                    }
                    HStack {
                        TextField("宽 (mm)", value: $model.document.layers[index].width, format: .number.precision(.fractionLength(1)))
                        TextField("高 (mm)", value: $model.document.layers[index].height, format: .number.precision(.fractionLength(1)))
                    }
                    TextField("旋转角度", value: $model.document.layers[index].rotation, format: .number)
                    Picker("移动步长", selection: $nudgeStep) {
                        Text("0.1 mm").tag(0.1)
                        Text("0.5 mm").tag(0.5)
                        Text("1 mm").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    Toggle("拖动时吸附 0.5 mm 网格", isOn: $snapToGrid)
                    HStack(spacing: 5) {
                        alignmentButton("align.horizontal.left", "左对齐", .left)
                        alignmentButton("align.horizontal.center", "水平居中", .horizontalCenter)
                        alignmentButton("align.horizontal.right", "右对齐", .right)
                        Divider().frame(height: 20)
                        alignmentButton("align.vertical.top", "顶对齐", .top)
                        alignmentButton("align.vertical.center", "垂直居中", .verticalCenter)
                        alignmentButton("align.vertical.bottom", "底对齐", .bottom)
                    }
                    NudgePad(step: nudgeStep) { dx, dy in
                        model.nudgeSelectedLayer(dx: dx, dy: dy)
                    }
                    Text("画布聚焦后可按方向键移动；Shift＋方向键每次移动 1 mm。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(model.document.layers[index].isLocked)
            } else {
                Section("标签") {
                    TextField("名称", text: $model.document.name)
                    HStack {
                        TextField("宽 (mm)", value: $model.document.paper.widthMM, format: .number)
                        TextField("高 (mm)", value: $model.document.paper.heightMM, format: .number)
                    }
                    Picker("纸张类型", selection: $model.paperMode) {
                        ForEach(P1PaperMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    if model.paperMode != .continuous {
                        Stepper(
                            "间隙长度：\(model.gapLengthMM) mm",
                            value: $model.gapLengthMM,
                            in: 1...10
                        )
                    }
                    Text(model.paperMode == .continuous
                         ? "连续纸使用固定走纸距离。"
                         : "打印结束后由传感器按设定间隙将下一张标签送到起始位置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup(isExpanded: $isPrintOffsetExpanded) {
                    LabeledContent("左右偏移") {
                        TextField("mm", value: $model.calibrationOffsetX, format: .number.precision(.fractionLength(1)))
                            .frame(width: 74)
                        Stepper("", value: $model.calibrationOffsetX, in: -10...10, step: 0.1)
                            .labelsHidden()
                    }
                    LabeledContent("上下偏移") {
                        TextField("mm", value: $model.calibrationOffsetY, format: .number.precision(.fractionLength(1)))
                            .frame(width: 74)
                        Stepper("", value: $model.calibrationOffsetY, in: -10...10, step: 0.1)
                            .labelsHidden()
                    }
                    Text("负值向左/向上，正值向右/向下；打印时按 0.125 mm/点舍入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("标签纸默认按 P1 打印头右侧对齐。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } label: {
                    Text("打印偏移")
                        .foregroundStyle(model.hasNonZeroPrintOffset ? Color.red : Color.primary)
                }

                DisclosureGroup("批量标签", isExpanded: $isBatchExpanded) {
                    Stepper("起始序号：\(model.serialStart)", value: $model.serialStart, in: 0...999_999)
                    if model.batchRecords.isEmpty {
                        Stepper("生成数量：\(model.serialCount)", value: $model.serialCount, in: 1...999)
                        Text("在文字或条码中输入 {{序号}} 生成连续编号。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("CSV 数据", value: "\(model.batchRecords.count) 行")
                        Button("清除 CSV 数据", role: .destructive) {
                            model.clearBatchData()
                        }
                    }
                    HStack {
                        Button("导入 CSV…", systemImage: "tablecells") {
                            model.requestImportCSV()
                        }
                        Button("生成并打印…", systemImage: "printer") {
                            model.prepareBatchPrint()
                        }
                        .disabled(model.document.layers.isEmpty)
                    }
                    Text("CSV 第一行是字段名；用 {{字段名}} 插入对应内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .background(InspectorFocusBridge())
    }

    private var selectedIndex: Int? {
        guard let selectedLayerID = model.selectedLayerID else { return nil }
        return model.document.layers.firstIndex { $0.id == selectedLayerID }
    }

    private func alignmentButton(
        _ systemImage: String,
        _ help: String,
        _ alignment: LayerAlignment
    ) -> some View {
        Button {
            model.alignSelection(alignment)
        } label: {
            Image(systemName: systemImage).frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .help(help)
        .disabled(!model.canAlignSelection)
    }
}

private struct NudgePad: View {
    let step: Double
    let nudge: (Double, Double) -> Void

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 28, height: 1)
                nudgeButton("arrow.up", help: "向上移动") { nudge(0, -step) }
                Color.clear.frame(width: 28, height: 1)
            }
            GridRow {
                nudgeButton("arrow.left", help: "向左移动") { nudge(-step, 0) }
                Image(systemName: "move.3d")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 24)
                nudgeButton("arrow.right", help: "向右移动") { nudge(step, 0) }
            }
            GridRow {
                Color.clear.frame(width: 28, height: 1)
                nudgeButton("arrow.down", help: "向下移动") { nudge(0, step) }
                Color.clear.frame(width: 28, height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func nudgeButton(_ image: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image).frame(width: 28, height: 22)
        }
        .buttonStyle(.bordered)
        .help("\(help) \(step.formatted()) mm")
    }
}

private struct TextContentSection: View {
    @Binding var layer: LabelLayer
    private static let fontFamilies = NSFontManager.shared.availableFontFamilies

    var body: some View {
        if layer.kind == .text {
            Section("文字") {
                TextField("内容", text: $layer.text, axis: .vertical)
                    .lineLimit(3...7)
                Picker("字体", selection: $layer.fontName) {
                    Text("系统字体").tag(".AppleSystemUIFont")
                    Divider()
                    ForEach(Self.fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: layer.fontName) { oldValue, newValue in
                    updateAutomaticHeight(oldFamily: oldValue, newFamily: newValue)
                }
                TextField("字号 (mm)", value: $layer.fontSizeMM, format: .number.precision(.fractionLength(1)))
                    .onChange(of: layer.fontSizeMM) { oldValue, newValue in
                        if LabelTextMetrics.isAutomaticHeight(
                            layer.height,
                            family: layer.fontName,
                            fontSizeMM: oldValue,
                            isBold: layer.isBold,
                            isItalic: layer.isItalic
                        ) {
                            layer.height = LabelTextMetrics.automaticHeightMM(
                                family: layer.fontName,
                                fontSizeMM: newValue,
                                isBold: layer.isBold,
                                isItalic: layer.isItalic
                            )
                        }
                    }
                HStack(spacing: 6) {
                    FormatToggle(title: "粗体", systemImage: "bold", isOn: $layer.isBold)
                    FormatToggle(title: "斜体", systemImage: "italic", isOn: $layer.isItalic)
                    FormatToggle(title: "下划线", systemImage: "underline", isOn: $layer.isUnderline)
                    FormatToggle(title: "删除线", systemImage: "strikethrough", isOn: $layer.isStrikethrough)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("文字格式")
                .onChange(of: layer.isBold) { oldValue, newValue in
                    updateAutomaticHeight(oldBold: oldValue, newBold: newValue)
                }
                .onChange(of: layer.isItalic) { oldValue, newValue in
                    updateAutomaticHeight(oldItalic: oldValue, newItalic: newValue)
                }
                Picker("对齐", selection: $layer.textAlignment) {
                    Label("左对齐", systemImage: "text.alignleft").tag(LabelTextAlignment.leading)
                    Label("居中", systemImage: "text.aligncenter").tag(LabelTextAlignment.center)
                    Label("右对齐", systemImage: "text.alignright").tag(LabelTextAlignment.trailing)
                }
                .pickerStyle(.segmented)
            }
        } else if layer.kind == .qrCode || layer.kind == .barcode {
            Section("文字") {
                TextField(
                    layer.kind == .qrCode ? "内容或网址" : "条码内容",
                    text: $layer.text,
                    axis: .vertical
                )
                    .lineLimit(2...5)
                Text(layer.kind == .qrCode
                     ? "二维码以无插值黑白点阵打印。"
                     : "使用 Code 128 编码；建议使用拉丁字母、数字和常用符号。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if layer.kind == .image {
            Section("图片") {
                Picker("画布预览", selection: $layer.imagePreviewMode) {
                    ForEach(LabelImagePreviewMode.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                Picker("缩放", selection: $layer.imageScaleMode) {
                    ForEach(LabelImageScaleMode.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                Picker("黑白算法", selection: $layer.imageAlgorithm) {
                    ForEach(LabelImageAlgorithm.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.menu)
                Text(layer.imageAlgorithm.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $layer.imageThreshold, in: 0.05...0.95) {
                    Text(layer.imageAlgorithm == .otsu
                         ? "黑色阈值：自动计算"
                         : "黑色阈值 \(Int((layer.imageThreshold * 100).rounded()))%")
                } minimumValueLabel: {
                    Image(systemName: "sun.max")
                } maximumValueLabel: {
                    Image(systemName: "moon")
                }
                .disabled(layer.imageAlgorithm == .otsu)
                Text(layer.imagePreviewMode == .printResult
                     ? "画布显示最终热敏打印点阵。"
                     : "彩色和灰度仅用于编辑预览；打印时仍使用所选黑白算法。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("文字") {
                Text("当前对象没有文字属性。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updateAutomaticHeight(oldFamily: String, newFamily: String) {
        guard LabelTextMetrics.isAutomaticHeight(
            layer.height,
            family: oldFamily,
            fontSizeMM: layer.fontSizeMM,
            isBold: layer.isBold,
            isItalic: layer.isItalic
        ) else { return }
        layer.height = LabelTextMetrics.automaticHeightMM(
            family: newFamily,
            fontSizeMM: layer.fontSizeMM,
            isBold: layer.isBold,
            isItalic: layer.isItalic
        )
    }

    private func updateAutomaticHeight(oldBold: Bool, newBold: Bool) {
        guard LabelTextMetrics.isAutomaticHeight(
            layer.height,
            family: layer.fontName,
            fontSizeMM: layer.fontSizeMM,
            isBold: oldBold,
            isItalic: layer.isItalic
        ) else { return }
        layer.height = LabelTextMetrics.automaticHeightMM(
            family: layer.fontName,
            fontSizeMM: layer.fontSizeMM,
            isBold: newBold,
            isItalic: layer.isItalic
        )
    }

    private func updateAutomaticHeight(oldItalic: Bool, newItalic: Bool) {
        guard LabelTextMetrics.isAutomaticHeight(
            layer.height,
            family: layer.fontName,
            fontSizeMM: layer.fontSizeMM,
            isBold: layer.isBold,
            isItalic: oldItalic
        ) else { return }
        layer.height = LabelTextMetrics.automaticHeightMM(
            family: layer.fontName,
            fontSizeMM: layer.fontSizeMM,
            isBold: layer.isBold,
            isItalic: newItalic
        )
    }
}

private struct FormatToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .help(title)
        .accessibilityLabel(title)
    }
}
