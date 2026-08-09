import Foundation

/// Owns document-related disk work so UI models only coordinate state changes.
/// The synchronous entry points keep command-line and test workflows simple;
/// interactive callers should use the asynchronous variants.
enum DocumentFileService {
    private static let maximumDocumentBytes = 256 * 1_024 * 1_024
    private static let maximumCSVBytes = 32 * 1_024 * 1_024
    private static let maximumImageBytes = 128 * 1_024 * 1_024

    struct ImportedImage: Sendable {
        let data: Data
        let aspectRatio: Double
    }

    static func write(_ document: LabelDocument, to url: URL) throws {
        try validate(document)
        try withSecurityScopedAccess(to: url) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
        }
    }

    static func readDocument(from url: URL) throws -> LabelDocument {
        try withSecurityScopedAccess(to: url) {
            let data = try readData(
                from: url,
                maximumBytes: maximumDocumentBytes,
                kind: "标签文件"
            )
            let document = try JSONDecoder().decode(LabelDocument.self, from: data)
            try validate(document)
            return document
        }
    }

    static func readCSVRecords(from url: URL) throws -> [[String: String]] {
        try withSecurityScopedAccess(to: url) {
            try CSVBatchParser.records(from: readData(
                from: url,
                maximumBytes: maximumCSVBytes,
                kind: "CSV 文件"
            ))
        }
    }

    static func readImage(from url: URL) throws -> ImportedImage {
        try withSecurityScopedAccess(to: url) {
            let data = try readData(
                from: url,
                maximumBytes: maximumImageBytes,
                kind: "图片"
            )
            guard let aspectRatio = LabelImageProcessor.sourceAspectRatio(data: data) else {
                throw DocumentFileError.invalidImage
            }
            return ImportedImage(data: data, aspectRatio: aspectRatio)
        }
    }

    static func writeAsync(_ document: LabelDocument, to url: URL) async throws {
        try await runDetached {
            try Task.checkCancellation()
            try write(document, to: url)
            try Task.checkCancellation()
        }
    }

    static func readDocumentAsync(from url: URL) async throws -> LabelDocument {
        try await runDetached {
            try Task.checkCancellation()
            return try readDocument(from: url)
        }
    }

    static func readCSVRecordsAsync(from url: URL) async throws -> [[String: String]] {
        try await runDetached {
            try Task.checkCancellation()
            return try readCSVRecords(from: url)
        }
    }

    static func readImageAsync(from url: URL) async throws -> ImportedImage {
        try await runDetached {
            try Task.checkCancellation()
            return try readImage(from: url)
        }
    }

    private static func runDetached<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func withSecurityScopedAccess<Value>(
        to url: URL,
        operation: () throws -> Value
    ) rethrows -> Value {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    private static func readData(
        from url: URL,
        maximumBytes: Int,
        kind: String
    ) throws -> Data {
        if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > maximumBytes {
            throw DocumentFileError.fileTooLarge(kind: kind, maximumMegabytes: maximumBytes / 1_024 / 1_024)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumBytes else {
            throw DocumentFileError.fileTooLarge(kind: kind, maximumMegabytes: maximumBytes / 1_024 / 1_024)
        }
        return data
    }

    private static func validate(_ document: LabelDocument) throws {
        guard P1PrintGeometry.supports(document.paper),
              document.layers.count <= 10_000,
              document.layers.allSatisfy(P1PrintGeometry.supports) else {
            throw DocumentFileError.invalidDocumentGeometry
        }
    }
}

enum DocumentFileError: LocalizedError {
    case invalidImage
    case invalidDocumentGeometry
    case fileTooLarge(kind: String, maximumMegabytes: Int)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "无法读取该图片。请使用 PNG、JPEG、HEIC、TIFF、GIF 或 PDF 图片。"
        case .invalidDocumentGeometry:
            "标签文件包含无效的纸张或元素尺寸。"
        case let .fileTooLarge(kind, maximumMegabytes):
            "\(kind)过大，最大支持 \(maximumMegabytes) MB。"
        }
    }
}
