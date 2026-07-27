import SwiftUI

struct SDKSupportView: View {
    var body: some View {
        List {
            Section {
                Text("依据德佟 LPAPI 公开头文件逐项核对。P1 Label 覆盖桌面打印所需功能；iOS 专属接口使用 macOS 原生实现替代，固件升级出于设备安全暂不开放。")
                    .foregroundStyle(.secondary)
            }
            ForEach(SDKSupportLevel.allCases, id: \.self) { level in
                Section(level.title) {
                    ForEach(SDKCapability.all.filter { $0.level == level }) { item in
                        LabeledContent {
                            Text(item.detail)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        } label: {
                            Label(item.name, systemImage: icon(for: level))
                        }
                    }
                }
            }
        }
        .navigationTitle("SDK 功能支持")
    }

    private func icon(for level: SDKSupportLevel) -> String {
        switch level {
        case .supported: "checkmark.circle.fill"
        case .nativeAlternative: "arrow.triangle.2.circlepath"
        case .notApplicable: "minus.circle"
        case .intentionallyUnavailable: "lock.shield"
        }
    }
}
