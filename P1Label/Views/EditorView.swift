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
