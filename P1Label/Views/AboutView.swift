import SwiftUI

struct AboutView: View {
    @State private var updateState: UpdateState = .idle

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
            LabeledContent("开源协议", value: "MIT")

            updateStatus

            HStack {
                Button("检查更新", systemImage: "arrow.clockwise") {
                    Task { await checkForUpdates(force: true) }
                }
                .disabled(updateState.isChecking)

                Link(
                    "打开项目仓库",
                    destination: URL(string: "https://github.com/louis16s/P1_label")!
                )
            }
        }
        .frame(width: 380)
        .padding(28)
        .task {
            await checkForUpdates(force: false)
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateState {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查更新…")
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("当前已是最新版本", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .available(update):
            HStack {
                Label("发现新版本 \(update.version)", systemImage: "arrow.down.circle.fill")
                Spacer()
                Link("下载更新", destination: update.releaseURL)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func checkForUpdates(force: Bool) async {
        if !force, updateState != .idle {
            return
        }

        updateState = .checking
        do {
            if let update = try await UpdateChecker.availableUpdate(currentVersion: version) {
                updateState = .available(update)
            } else {
                updateState = .upToDate
            }
        } catch {
            updateState = .failed("暂时无法检查更新，请稍后重试")
        }
    }
}

private enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(AppUpdate)
    case failed(String)

    var isChecking: Bool {
        self == .checking
    }
}
