import Foundation

/// Serializes interactive document I/O. Cancellation alone cannot stop a
/// filesystem write that has already entered the kernel, so every operation
/// waits for its predecessor before touching a label file.
actor DocumentFileAccess {
    private var tail: Task<Void, Never>?

    func write(_ document: LabelDocument, to url: URL) async throws {
        try await enqueue {
            try await DocumentFileService.writeAsync(document, to: url)
        }
    }

    func readDocument(from url: URL) async throws -> LabelDocument {
        try await enqueue {
            try await DocumentFileService.readDocumentAsync(from: url)
        }
    }

    func readCSV(from url: URL) async throws -> [[String: String]] {
        try await enqueue {
            try await DocumentFileService.readCSVRecordsAsync(from: url)
        }
    }

    func readImage(from url: URL) async throws -> DocumentFileService.ImportedImage {
        try await enqueue {
            try await DocumentFileService.readImageAsync(from: url)
        }
    }

    private func enqueue<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let predecessor = tail
        let task = Task<Value, Error> {
            await predecessor?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task {
            _ = try? await task.value
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
