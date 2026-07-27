import SwiftUI
import UniformTypeIdentifiers

struct LabelBackupFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var document: LabelDocument

    init(document: LabelDocument) {
        self.document = document
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.invalidFile
        }
        document = try JSONDecoder().decode(LabelDocument.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(document))
    }

    enum BackupError: LocalizedError {
        case invalidFile

        var errorDescription: String? {
            "这个文件不是有效的 P1 Label 标签备份。"
        }
    }
}
