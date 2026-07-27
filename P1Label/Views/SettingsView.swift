import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("打印校准") {
                TextField("左右偏移 (mm)", value: $model.calibrationOffsetX, format: .number)
                TextField("上下偏移 (mm)", value: $model.calibrationOffsetY, format: .number)
                Text("负值向左/向上，正值向右/向下；设置会自动保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 380)
    }
}
