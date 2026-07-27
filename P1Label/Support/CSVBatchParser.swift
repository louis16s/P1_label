import Foundation

enum CSVBatchParser {
    static func records(from data: Data) throws -> [[String: String]] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CSVError.invalidEncoding
        }
        let rows = try parseRows(text)
        guard let headers = rows.first, !headers.isEmpty else {
            throw CSVError.missingHeader
        }
        return rows.dropFirst().filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }.enumerated().map { index, row in
            var record: [String: String] = ["序号": String(index + 1)]
            for (column, header) in headers.enumerated() {
                let key = header.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                record[key] = column < row.count ? row[column] : ""
            }
            return record
        }
    }

    private static func parseRows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if character == "\n", !quoted {
                row.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        guard !quoted else {
            throw CSVError.malformedQuotes
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
            rows.append(row)
        }
        return rows
    }

    enum CSVError: LocalizedError {
        case invalidEncoding
        case missingHeader
        case malformedQuotes

        var errorDescription: String? {
            switch self {
            case .invalidEncoding: "CSV 必须使用 UTF-8 编码。"
            case .missingHeader: "CSV 第一行必须包含字段名。"
            case .malformedQuotes: "CSV 包含未闭合的引号，请检查导出文件。"
            }
        }
    }
}
