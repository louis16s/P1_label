import SwiftUI

struct AboutView: View {
    @State private var updateState: UpdateState = .idle

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var body: some View {
        VStack(spacing: 20) {
            AboutIdentityHeader(version: version)

            VStack(spacing: 0) {
                AboutDetailRow(title: "作者", value: "louis16s", systemImage: "person.crop.circle")
                Divider().padding(.leading, 38)
                AboutDetailRow(
                    title: "适用系统",
                    value: "macOS 26 · Apple 芯片",
                    systemImage: "desktopcomputer"
                )
            }
            .padding(.horizontal, 14)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))

            updateStatus
                .frame(minHeight: 22)

            HStack(spacing: 10) {
                Button("检查更新", systemImage: "arrow.clockwise") {
                    Task { await checkForUpdates(force: true) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updateState.isChecking)

                Link(
                    "打开项目仓库",
                    destination: URL(string: "https://github.com/louis16s/P1_label")!
                )
                .buttonStyle(.bordered)
            }
        }
        .frame(width: 400)
        .padding(30)
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

private struct AboutIdentityHeader: View {
    let version: String

    var body: some View {
        VStack(spacing: 10) {
            if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
            }

            VStack(spacing: 5) {
                Text("P1 Label")
                    .font(.title.bold())
                Text("德佟 P1 标签设计与打印工具")
                    .foregroundStyle(.secondary)
            }

            Text("版本 \(version)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }
}

private struct AboutDetailRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 11)
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
