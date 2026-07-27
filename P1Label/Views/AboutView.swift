import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
            }
            Text("P1 Label")
                .font(.title.bold())
            Text("版本 \(version)")
                .foregroundStyle(.secondary)
            Text("德佟 P1 标签设计与打印工具")
            Divider()
            LabeledContent("作者", value: "louis16s")
            LabeledContent("适用系统", value: "macOS 26 · Apple 芯片")
            Link("查看项目源代码", destination: URL(string: "https://github.com/louis16s/P1_label")!)
        }
        .frame(width: 360)
        .padding(28)
    }
}
