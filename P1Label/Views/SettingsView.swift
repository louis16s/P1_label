import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            PrintOffsetSettingsSection(model: model)
            PhotoCalibrationSettingsSection(model: model)

            Section("默认打印") {
                Stepper("默认份数：\(model.printCopies)", value: $model.printCopies, in: 1...99)
                Toggle("反色打印", isOn: $model.printInverted)
                Text("纸张类型、间隙、浓度和速度属于目标打印机，在“打印机”窗口中设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("版本") {
                LabeledContent("软件", value: "P1 Label")
                LabeledContent("作者", value: "louis16s")
                LabeledContent("平台", value: "macOS 26 · Apple 芯片")
            }
        }
        .padding()
        .frame(width: 460)
    }
}

private struct PrintOffsetSettingsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section("打印偏移") {
            LabeledContent("左右偏移") {
                TextField(
                    "mm",
                    value: $model.calibrationOffsetX,
                    format: .number.precision(.fractionLength(1))
                )
                .frame(width: 72)
                Stepper("", value: $model.calibrationOffsetX, in: -10...10, step: 0.1)
                    .labelsHidden()
            }
            LabeledContent("上下偏移") {
                TextField(
                    "mm",
                    value: $model.calibrationOffsetY,
                    format: .number.precision(.fractionLength(1))
                )
                .frame(width: 72)
                Stepper("", value: $model.calibrationOffsetY, in: -10...10, step: 0.1)
                    .labelsHidden()
            }
            Text("输入精确到 0.1 mm；打印时按 0.125 mm/点舍入。负值向左/向上，正值向右/向下。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PhotoCalibrationSettingsSection: View {
    @Bindable var model: AppModel
    @State private var isAnalyzingPhoto = false
    @State private var calibrationResult: PhotoCalibrationResult?
    @State private var calibrationError: String?
    @State private var selectedPhotoName: String?

    var body: some View {
        Section("照片自动校准") {
            calibrationStep(
                number: 1,
                title: "打印定位标签",
                detail: model.hasConnectedPrinter
                    ? "使用当前 \(model.document.paper.displayName) 纸张生成定位图案。"
                    : "请先在“打印机”窗口连接德佟 P1。"
            ) {
                Button("打印定位标签…", systemImage: "printer") {
                    model.prepareTestPrint()
                }
                .disabled(!model.hasConnectedPrinter)
                .alert("确认打印定位标签", isPresented: calibrationPrintConfirmation) {
                    Button("取消", role: .cancel) { model.cancelPendingPrint() }
                    Button("确认打印") { model.confirmPendingPrint() }
                } message: {
                    Text("将打印一张用于照片识别的定位标签，并套用当前打印偏移。纸张会移动。")
                }
            }

            Divider()

            calibrationStep(
                number: 2,
                title: "导入打印结果",
                detail: "取下标签，单独平放在深色背景上，并完整拍到四条纸边。"
            ) {
                EmptyView()
            }

            Button(action: chooseCalibrationPhoto) {
                HStack(spacing: 10) {
                    Image(systemName: selectedPhotoName == nil ? "photo.badge.plus" : "photo.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedPhotoName ?? "选择或拖入定位标签照片")
                            .foregroundStyle(.primary)
                        Text("支持 HEIC、JPEG、PNG；照片不会保存到标签文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isAnalyzingPhoto {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .contentShape(Rectangle())
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            Color.secondary.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isAnalyzingPhoto)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                analyzePhoto(at: url)
                return true
            }
            .alert(
                "无法自动校准",
                isPresented: Binding(
                    get: { calibrationError != nil },
                    set: { if !$0 { calibrationError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(calibrationError ?? "")
            }

            if let calibrationResult {
                Divider()
                calibrationStep(
                    number: 3,
                    title: "确认校准结果",
                    detail: "识别结果不会自动修改设置。"
                ) {
                    EmptyView()
                }
                LabeledContent(
                    "建议左右偏移",
                    value: "\(displayedOffset(calibrationResult.horizontalOffsetMM)) mm"
                )
                LabeledContent(
                    "建议上下偏移",
                    value: "\(displayedOffset(calibrationResult.verticalOffsetMM)) mm"
                )
                LabeledContent(
                    "识别置信度",
                    value: "\(calibrationResult.confidenceDescription) · \(Int(calibrationResult.confidence * 100))%"
                )
                HStack {
                    Button("应用校准") {
                        model.calibrationOffsetX = calibrationResult.horizontalOffsetMM
                        model.calibrationOffsetY = calibrationResult.verticalOffsetMM
                        self.calibrationResult = nil
                    }
                    .buttonStyle(.borderedProminent)
                    Button("重新选择") {
                        self.calibrationResult = nil
                        chooseCalibrationPhoto()
                    }
                }
            }
        }
    }

    private var calibrationPrintConfirmation: Binding<Bool> {
        Binding(
            get: { model.pendingPrint?.source == .calibration },
            set: { if !$0 { model.cancelPendingPrint() } }
        )
    }

    private func calibrationStep<Accessory: View>(
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }

    private func chooseCalibrationPhoto() {
        FilePanelService.chooseCalibrationPhoto { url in
            guard let url else { return }
            analyzePhoto(at: url)
        }
    }

    private func analyzePhoto(at url: URL) {
        isAnalyzingPhoto = true
        calibrationResult = nil
        calibrationError = nil
        selectedPhotoName = url.lastPathComponent
        let paper = model.document.paper
        let baseOffsetX = model.lastCalibrationPrintOffsetX
        let baseOffsetY = model.lastCalibrationPrintOffsetY
        let accessed = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let correction = try await Task.detached(priority: .userInitiated) {
                    try PhotoCalibrationAnalyzer.analyze(photoURL: url, paper: paper)
                }.value
                calibrationResult = correction.addingPrintedOffset(
                    horizontal: baseOffsetX,
                    vertical: baseOffsetY
                )
            } catch {
                calibrationError = error.localizedDescription
            }
            isAnalyzingPhoto = false
        }
    }

    private func displayedOffset(_ value: Double) -> String {
        ((value * 10).rounded() / 10).formatted(
            .number.precision(.fractionLength(1))
        )
    }
}
