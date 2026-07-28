import AppKit
import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            EditableCanvas(
                document: $model.document,
                selection: $model.selectedLayerID,
                selections: $model.selectedLayerIDs,
                moveSelection: model.nudgeSelectedLayer
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            EditorInspector(model: model)
                .frame(width: 310)
        }
        .navigationTitle("")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(model.document.paper.displayName)
                Text("·")
                Text("\(model.document.layers.count) 个对象")
                Spacer()
                Text(model.printStatus).foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
        }
    }
}

private struct EditableCanvas: View {
    @Binding var document: LabelDocument
    @Binding var selection: UUID?
    @Binding var selections: Set<UUID>
    let moveSelection: (Double, Double) -> Void
    @State private var zoom = 1.0
    @State private var editingObjectID: UUID?
    @AppStorage("nudgeStep") private var keyboardStep = 0.1
    @AppStorage("snapToGrid") private var snapToGrid = true

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("画布")
                    .font(.caption.weight(.medium))
                Spacer()
                Button { setZoom(zoom - 0.1) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                Text("\(Int((zoom * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 42)
                Button { setZoom(zoom + 0.1) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                Button("适应画布", systemImage: "arrow.down.right.and.arrow.up.left") { zoom = 1 }
                    .buttonStyle(.plain)
                    .help("将整张标签缩放到当前画布")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)

            GeometryReader { viewport in
                let fitScale = CanvasLayout.fitScale(
                    viewport: viewport.size,
                    paper: document.paper
                )
                let scale = fitScale * zoom
                let contentSize = CanvasLayout.contentSize(
                    viewport: viewport.size,
                    paper: document.paper,
                    scale: scale
                )

                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        Rectangle()
                            .fill(.background.secondary)
                            .contentShape(Rectangle())
                            .onTapGesture { clearSelection() }

                        paperCanvas(scale: scale)
                    }
                    .frame(width: contentSize.width, height: contentSize.height)
                }
                .scrollIndicators(zoom <= CanvasLayout.noScrollZoom ? .hidden : .automatic)
                .background(.background.secondary)
            }
        }
        .padding(.top, 12)
    }

    private func paperCanvas(scale: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.white)
                .allowsHitTesting(false)
            Rectangle()
                .stroke(.gray.opacity(0.45))
                .allowsHitTesting(false)
            alignmentGuides(scale: scale)
            ForEach($document.layers) { $layer in
                CanvasLayer(
                    layer: $layer,
                    isSelected: selections.contains(layer.id),
                    isEditing: editingObjectID == layer.id,
                    scale: scale,
                    keyboardStep: keyboardStep,
                    snapToGrid: snapToGrid,
                    paperWidth: document.paper.widthMM,
                    paperHeight: document.paper.heightMM,
                    moveSelection: moveSelection
                ) { additive in
                    select(layer.id, additive: additive)
                } beginEditing: {
                    select(layer.id, additive: false)
                    editingObjectID = layer.kind == .text ? layer.id : nil
                } endEditing: {
                    if editingObjectID == layer.id {
                        editingObjectID = nil
                    }
                }
            }
        }
        .frame(
            width: document.paper.widthMM * scale,
            height: document.paper.heightMM * scale,
            alignment: .topLeading
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    @ViewBuilder
    private func alignmentGuides(scale: Double) -> some View {
        if let selection,
           let layer = document.layers.first(where: { $0.id == selection }) {
            if abs(layer.x + layer.width / 2 - document.paper.widthMM / 2) < 0.01 {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 1, height: document.paper.heightMM * scale)
                    .position(x: document.paper.widthMM * scale / 2,
                              y: document.paper.heightMM * scale / 2)
                    .allowsHitTesting(false)
            }
            if abs(layer.y + layer.height / 2 - document.paper.heightMM / 2) < 0.01 {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: document.paper.widthMM * scale, height: 1)
                    .position(x: document.paper.widthMM * scale / 2,
                              y: document.paper.heightMM * scale / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func setZoom(_ value: Double) {
        zoom = min(2, max(0.5, (value * 10).rounded() / 10))
    }

    private func select(_ id: UUID, additive: Bool) {
        if additive {
            if selections.contains(id) {
                selections.remove(id)
                if selection == id {
                    selection = selections.first
                }
            } else {
                selections.insert(id)
                selection = id
            }
            editingObjectID = nil
            return
        }
        if selection != id || selections.count != 1 {
            editingObjectID = nil
        }
        selections = [id]
        selection = id
    }

    private func clearSelection() {
        selection = nil
        selections = []
        editingObjectID = nil
    }
}

private struct CanvasLayer: View {
    @Binding var layer: LabelLayer
    let isSelected: Bool
    let isEditing: Bool
    let scale: Double
    let keyboardStep: Double
    let snapToGrid: Bool
    let paperWidth: Double
    let paperHeight: Double
    let moveSelection: (Double, Double) -> Void
    let select: (Bool) -> Void
    let beginEditing: () -> Void
    let endEditing: () -> Void
    @State private var dragStart: CGPoint?
    @State private var resizeStart: LayerRect?
    @FocusState private var isTextFocused: Bool

    var body: some View {
        rendered
            .frame(
                width: max(2, layer.width * scale),
                height: max(2, layer.height * scale),
                alignment: .topLeading
            )
            .background {
                if layer.kind == .text, isSelected {
                    Rectangle()
                        .fill(Color.white.opacity(0.94))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if isSelected {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .overlay {
                if !isEditing {
                    CanvasLayerInputCapture(
                        normalStep: keyboardStep,
                        onSingleClick: select,
                        onDoubleClick: {
                            if !layer.isLocked, layer.kind == .text {
                                beginEditing()
                            } else {
                                select(false)
                            }
                        },
                        onMove: { dx, dy in
                            guard !layer.isLocked else { return }
                            moveSelection(dx, dy)
                        },
                        onDrag: { translation in
                            guard !layer.isLocked else { return }
                            if dragStart == nil {
                                dragStart = CGPoint(x: layer.x, y: layer.y)
                                if !isSelected { select(false) }
                            }
                            guard let dragStart else { return }
                            layer.x = snappedX(dragStart.x + translation.width / scale)
                            layer.y = snappedY(dragStart.y + translation.height / scale)
                        },
                        onDragEnded: { dragStart = nil }
                    )
                    .accessibilityLabel(layer.name)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if layer.isLocked {
                    LockBadge(
                        keyboardStep: keyboardStep,
                        select: { select(false) },
                        unlock: {
                            layer.isLocked = false
                            select(false)
                        }
                    )
                    .offset(x: 7, y: 7)
                }
            }
            .overlay {
                if isSelected, !layer.isLocked {
                    ResizeHandles(
                        keyboardStep: keyboardStep,
                        select: { select(false) }
                    ) { handle, translation in
                        resize(handle: handle, translation: translation)
                    }
                    .frame(
                        width: max(2, layer.width * scale),
                        height: max(2, layer.height * scale)
                    )
                }
            }
            .rotationEffect(.degrees(layer.rotation))
            .position(
                x: (layer.x + layer.width / 2) * scale,
                y: (layer.y + layer.height / 2) * scale
            )
            .onChange(of: isTextFocused) { oldValue, newValue in
                if oldValue, !newValue, isEditing {
                    endEditing()
                }
            }
            .onChange(of: layer.isLocked) { _, isLocked in
                if isLocked, isEditing {
                    endEditing()
                }
            }
            .contextMenu {
                Button(layer.isLocked ? "解锁元素" : "锁定元素",
                       systemImage: layer.isLocked ? "lock.open" : "lock") {
                    layer.isLocked.toggle()
                    select(false)
                }
            }
    }

    private func resize(handle: ResizeHandlePosition, translation: CGSize?) {
        guard let translation else {
            resizeStart = nil
            return
        }
        if resizeStart == nil {
            resizeStart = LayerRect(
                x: layer.x,
                y: layer.y,
                width: layer.width,
                height: layer.height
            )
        }
        guard let resizeStart else { return }
        let dx = translation.width / scale
        let dy = translation.height / scale
        let minimum = 1.0
        let left = resizeStart.x
        let right = resizeStart.x + resizeStart.width
        let top = resizeStart.y
        let bottom = resizeStart.y + resizeStart.height

        if handle.movesLeft {
            let newLeft = min(right - minimum, max(0, snap(left + dx)))
            layer.x = newLeft
            layer.width = right - newLeft
        } else if handle.movesRight {
            let newRight = max(left + minimum, min(paperWidth, snap(right + dx)))
            layer.x = left
            layer.width = newRight - left
        }

        if handle.movesTop {
            let newTop = min(bottom - minimum, max(0, snap(top + dy)))
            layer.y = newTop
            layer.height = bottom - newTop
        } else if handle.movesBottom {
            let newBottom = max(top + minimum, min(paperHeight, snap(bottom + dy)))
            layer.y = top
            layer.height = newBottom - top
        }
    }

    private func clampedX(_ value: Double) -> Double {
        min(max(0, value), max(0, paperWidth - layer.width))
    }

    private func clampedY(_ value: Double) -> Double {
        min(max(0, value), max(0, paperHeight - layer.height))
    }

    private func snappedX(_ value: Double) -> Double {
        let centered = paperWidth / 2 - layer.width / 2
        if abs(value - centered) < 0.3 { return clampedX(centered) }
        return clampedX(snap(value))
    }

    private func snappedY(_ value: Double) -> Double {
        let centered = paperHeight / 2 - layer.height / 2
        if abs(value - centered) < 0.3 { return clampedY(centered) }
        return clampedY(snap(value))
    }

    private func snap(_ value: Double) -> Double {
        snapToGrid ? (value * 2).rounded() / 2 : value
    }

    @ViewBuilder private var rendered: some View {
        switch layer.kind {
        case .text:
            if isEditing {
                TextField("文字", text: $layer.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.custom(layer.fontName, size: max(8, layer.fontSizeMM * scale)))
                    .fontWeight(layer.isBold ? .bold : .regular)
                    .italic(layer.isItalic)
                    .underline(layer.isUnderline)
                    .strikethrough(layer.isStrikethrough)
                    .multilineTextAlignment(layer.textAlignment.swiftUIAlignment)
                    .foregroundStyle(.black)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
                    .focused($isTextFocused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layer.textAlignment.frameAlignment)
                    .onAppear {
                        DispatchQueue.main.async { isTextFocused = true }
                    }
                    .onExitCommand { endEditing() }
            } else {
                Text(layer.text.isEmpty ? "文字" : layer.text)
                    .font(.custom(layer.fontName, size: max(8, layer.fontSizeMM * scale)))
                    .fontWeight(layer.isBold ? .bold : .regular)
                    .italic(layer.isItalic)
                    .underline(layer.isUnderline)
                    .strikethrough(layer.isStrikethrough)
                    .multilineTextAlignment(layer.textAlignment.swiftUIAlignment)
                    .foregroundStyle(.black)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layer.textAlignment.frameAlignment)
            }
        case .rectangle:
            Rectangle().stroke(.black, lineWidth: max(1, scale / 5))
        case .ellipse:
            Ellipse().stroke(.black, lineWidth: max(1, scale / 5))
        case .line:
            Path {
                $0.move(to: .zero)
                $0.addLine(to: CGPoint(x: layer.width * scale, y: layer.height * scale))
            }
            .stroke(.black, lineWidth: max(1, scale / 5))
        case .qrCode:
            QRCodeView(value: layer.text)
        case .barcode:
            if let image = LabelPreviewCache.shared.barcode(layer.text) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "barcode").resizable().scaledToFit()
            }
        case .image:
            if let image = LabelPreviewCache.shared.imagePreview(for: layer, scale: scale) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(layer.imagePreviewMode == .printResult ? .none : .high)
                    .aspectRatio(contentMode: layer.imageScaleMode == .fit ? .fit : .fill)
                    .clipped()
            } else {
                Image(systemName: "photo").resizable().scaledToFit().foregroundStyle(.secondary).padding(4)
            }
        }
    }
}

private struct LockBadge: View {
    let keyboardStep: Double
    let select: () -> Void
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            CanvasLayerInputCapture(
                normalStep: keyboardStep,
                onSingleClick: { _ in select() },
                onDoubleClick: unlock,
                onMove: { _, _ in },
                onDrag: { _ in },
                onDragEnded: {}
            )
        }
        .frame(width: 22, height: 22)
        .help("已锁定；双击解锁")
        .accessibilityLabel("已锁定；双击解锁")
    }
}

private struct ResizeHandles: View {
    let keyboardStep: Double
    let select: () -> Void
    let onDrag: (ResizeHandlePosition, CGSize?) -> Void

    var body: some View {
        GeometryReader { geometry in
            ForEach(ResizeHandlePosition.allCases) { handle in
                ResizeBadge(
                    keyboardStep: keyboardStep,
                    select: select,
                    onDrag: { onDrag(handle, $0) }
                )
                .position(handle.position(in: geometry.size))
            }
        }
    }
}

private struct ResizeBadge: View {
    let keyboardStep: Double
    let select: () -> Void
    let onDrag: (CGSize?) -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .stroke(Color.accentColor, lineWidth: 1.5)
                .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            CanvasLayerInputCapture(
                normalStep: keyboardStep,
                onSingleClick: { _ in select() },
                onDoubleClick: select,
                onMove: { _, _ in },
                onDrag: { onDrag($0) },
                onDragEnded: { onDrag(nil) }
            )
        }
        .frame(width: 12, height: 12)
        .help("拖动调整元素大小")
        .accessibilityLabel("调整元素大小")
    }
}

private struct LayerRect {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private enum ResizeHandlePosition: String, CaseIterable, Identifiable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var id: String { rawValue }
    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    func position(in size: CGSize) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: 0, y: 0)
        case .top: CGPoint(x: size.width / 2, y: 0)
        case .topRight: CGPoint(x: size.width, y: 0)
        case .right: CGPoint(x: size.width, y: size.height / 2)
        case .bottomRight: CGPoint(x: size.width, y: size.height)
        case .bottom: CGPoint(x: size.width / 2, y: size.height)
        case .bottomLeft: CGPoint(x: 0, y: size.height)
        case .left: CGPoint(x: 0, y: size.height / 2)
        }
    }
}

private extension LabelTextAlignment {
    var swiftUIAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }
}

private struct QRCodeView: View {
    let value: String

    var body: some View {
        if let image = LabelPreviewCache.shared.qrCode(value) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit()
        }
    }

}

private struct EditorInspector: View {
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
