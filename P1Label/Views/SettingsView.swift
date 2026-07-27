import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var isAnalyzingPhoto = false
    @State private var calibrationResult: PhotoCalibrationResult?
    @State private var calibrationError: String?

    var body: some View {
        Form {
            Section("打印校准") {
                TextField("左右偏移 (mm)", value: $model.calibrationOffsetX, format: .number)
                TextField("上下偏移 (mm)", value: $model.calibrationOffsetY, format: .number)
                Text("负值向左/向上，正值向右/向下；设置会自动保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Button("从定位标签照片自动校准…", systemImage: "camera.viewfinder") {
                    chooseCalibrationPhoto()
                }
                .disabled(isAnalyzingPhoto)
                if isAnalyzingPhoto {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在识别纸张边缘与定位框…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let calibrationResult {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(
                            "建议左右偏移",
                            value: "\(calibrationResult.horizontalOffsetMM.formatted(.number.precision(.fractionLength(2)))) mm"
                        )
                        LabeledContent(
                            "建议上下偏移",
                            value: "\(calibrationResult.verticalOffsetMM.formatted(.number.precision(.fractionLength(2)))) mm"
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
                            Button("取消") {
                                self.calibrationResult = nil
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Section("打印参数") {
                Stepper("间隙长度：\(model.gapLengthMM) mm", value: $model.gapLengthMM, in: 1...10)
                Stepper("默认份数：\(model.printCopies)", value: $model.printCopies, in: 1...99)
                Toggle("反色打印", isOn: $model.printInverted)
                Text("反色会交换黑白打印区域，适合黑底白字标签。")
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
        .frame(width: 420)
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
    }

    private func chooseCalibrationPhoto() {
        FilePanelService.chooseCalibrationPhoto { url in
            guard let url else { return }
            isAnalyzingPhoto = true
            calibrationResult = nil
            let paper = model.document.paper
            Task {
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try PhotoCalibrationAnalyzer.analyze(photoURL: url, paper: paper)
                    }.value
                    calibrationResult = result
                } catch {
                    calibrationError = error.localizedDescription
                }
                isAnalyzingPhoto = false
            }
        }
    }
}
