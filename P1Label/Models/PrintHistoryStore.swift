import Foundation
import Observation

struct PrintHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case sending
        case succeeded
        case failed
        case cancelled

        var displayName: String {
            switch self {
            case .sending: "正在发送"
            case .succeeded: "已完成"
            case .failed: "失败"
            case .cancelled: "已取消"
            }
        }
    }

    let id: UUID
    let name: String
    let createdAt: Date
    let connection: String
    let byteCount: Int
    var status: Status
    var detail: String?
}

@MainActor
@Observable
final class PrintHistoryStore {
    private static let maximumEntryCount = 50
    private static let maximumRetryPayloadBytes = 32 * 1_024 * 1_024
    private static let defaultPersistenceKey = "printHistoryMetadata.v1"

    private(set) var entries: [PrintHistoryEntry]
    var hasActiveJobs: Bool { entries.contains { $0.status == .sending } }
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let persistenceKey: String
    @ObservationIgnored private var retryPayloads: [UUID: PendingPrint] = [:]
    @ObservationIgnored private var retryOrder: [UUID] = []
    @ObservationIgnored private var retainedPayloadBytes = 0

    init(
        preferences: UserDefaults = .standard,
        persistenceKey: String = PrintHistoryStore.defaultPersistenceKey
    ) {
        self.preferences = preferences
        self.persistenceKey = persistenceKey
        if let data = preferences.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode([PrintHistoryEntry].self, from: data) {
            entries = Array(decoded.prefix(Self.maximumEntryCount)).map { entry in
                var restored = entry
                restored = Self.limited(restored)
                if restored.status == .sending {
                    restored.status = .cancelled
                    restored.detail = "应用上次退出前未完成"
                }
                return restored
            }
        } else {
            entries = []
        }
        persist()
    }

    @discardableResult
    func begin(_ job: PendingPrint, connection: String) -> UUID {
        let id = UUID()
        entries.insert(
            PrintHistoryEntry(
                id: id,
                name: Self.limited(job.name, maximumCharacters: 200),
                createdAt: Date(),
                connection: Self.limited(connection, maximumCharacters: 100),
                byteCount: job.data.count,
                status: .sending,
                detail: nil
            ),
            at: 0
        )
        retain(job, for: id)
        trimEntries()
        persist()
        return id
    }

    func markSucceeded(_ id: UUID) {
        update(id, status: .succeeded, detail: nil)
    }

    func markFailed(_ id: UUID, message: String) {
        update(id, status: .failed, detail: PrinterStatusText.normalize(message))
    }

    func markCancelled(_ id: UUID, detail: String? = nil) {
        update(id, status: .cancelled, detail: detail)
    }

    func canRetry(_ id: UUID) -> Bool {
        retryPayloads[id] != nil
    }

    func retryJob(_ id: UUID) -> PendingPrint? {
        guard let job = retryPayloads[id] else { return nil }
        return PendingPrint(data: job.data, name: job.name, source: job.source)
    }

    func clear() {
        guard !hasActiveJobs else { return }
        entries.removeAll()
        retryPayloads.removeAll()
        retryOrder.removeAll()
        retainedPayloadBytes = 0
        persist()
    }

    private func update(_ id: UUID, status: PrintHistoryEntry.Status, detail: String?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = status
        entries[index].detail = detail.map { Self.limited($0, maximumCharacters: 500) }
        persist()
    }

    private func retain(_ job: PendingPrint, for id: UUID) {
        guard job.data.count <= Self.maximumRetryPayloadBytes else { return }
        while retainedPayloadBytes + job.data.count > Self.maximumRetryPayloadBytes,
              let oldest = retryOrder.first {
            retryOrder.removeFirst()
            if let removed = retryPayloads.removeValue(forKey: oldest) {
                retainedPayloadBytes -= removed.data.count
            }
        }
        retryPayloads[id] = job
        retryOrder.append(id)
        retainedPayloadBytes += job.data.count
    }

    private func trimEntries() {
        guard entries.count > Self.maximumEntryCount else { return }
        let removedIDs = Set(entries.dropFirst(Self.maximumEntryCount).map(\.id))
        entries.removeLast(entries.count - Self.maximumEntryCount)
        retryOrder.removeAll { id in
            guard removedIDs.contains(id) else { return false }
            if let removed = retryPayloads.removeValue(forKey: id) {
                retainedPayloadBytes -= removed.data.count
            }
            return true
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        preferences.set(data, forKey: persistenceKey)
    }

    private static func limited(_ entry: PrintHistoryEntry) -> PrintHistoryEntry {
        PrintHistoryEntry(
            id: entry.id,
            name: limited(entry.name, maximumCharacters: 200),
            createdAt: entry.createdAt,
            connection: limited(entry.connection, maximumCharacters: 100),
            byteCount: max(0, entry.byteCount),
            status: entry.status,
            detail: entry.detail.map { limited($0, maximumCharacters: 500) }
        )
    }

    private static func limited(_ value: String, maximumCharacters: Int) -> String {
        guard value.count > maximumCharacters else { return value }
        return String(value.prefix(maximumCharacters - 1)) + "…"
    }
}
