import Foundation

enum PrinterStatusText {
    nonisolated static func normalize(_ status: String) -> String {
        status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。.．"))
    }
}
