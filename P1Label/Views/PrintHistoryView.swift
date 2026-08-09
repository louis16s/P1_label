import SwiftUI

struct PrintHistoryView: View {
    @Bindable var model: AppModel
    @State private var confirmsClear = false

    private var store: PrintHistoryStore { model.printHistory }

    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "暂无打印历史",
                    systemImage: "printer",
                    description: Text("确认发送的打印任务会显示在这里")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.entries) { entry in
                    PrintHistoryRow(
                        entry: entry,
                        canRetry: store.canRetry(entry.id),
                        retry: { model.retryPrint(entry.id) },
                        cancel: { model.cancelPrintJob(entry.id) }
                    )
                }
            }
        }
        .navigationTitle("打印历史")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("清除历史", systemImage: "trash") {
                    confirmsClear = true
                }
                .disabled(store.entries.isEmpty || store.hasActiveJobs)
                .help(store.hasActiveJobs ? "打印任务完成或取消后才能清除历史" : "清除全部打印历史")
            }
        }
        .confirmationDialog(
            "清除全部打印历史？",
            isPresented: $confirmsClear
        ) {
            Button("清除历史", role: .destructive) { store.clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不会删除标签文件")
        }
        .alert("确认重新打印", isPresented: Binding(
            get: { model.pendingPrint?.source == .history },
            set: { if !$0 { model.cancelPendingPrint() } }
        )) {
            Button("取消", role: .cancel) { model.cancelPendingPrint() }
            Button("确认打印") { model.confirmPendingPrint() }
        } message: {
            Text(model.documentPrintConfirmationMessage)
        }
    }
}

private struct PrintHistoryRow: View {
    let entry: PrintHistoryEntry
    let canRetry: Bool
    let retry: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.status.displayName)
                        .foregroundStyle(statusColor)
                    Text("·")
                    Text(entry.connection)
                    Text("·")
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(entry.status == .failed ? .red : .secondary)
                        .lineLimit(2)
                }
                Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if entry.status == .sending {
                Button("取消") { cancel() }
            } else {
                Button("再次打印") { retry() }
                    .disabled(!canRetry)
                    .help(canRetry ? "重新确认并发送此任务" : "此任务的打印数据已释放")
            }
        }
        .padding(.vertical, 5)
    }

    private var statusIcon: String {
        switch entry.status {
        case .sending: "arrow.up.circle"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .sending: .accentColor
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}
