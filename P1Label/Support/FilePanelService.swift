import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanelService {
    static func chooseCalibrationPhoto(completion: @escaping @MainActor (URL?) -> Void) {
        let panel = openPanel(
            title: "从照片自动校准",
            message: "选择一张完整拍到定位标签四条纸边的照片",
            prompt: "分析",
            contentTypes: [.image]
        )
        present(panel, completion: completion)
    }

    static func chooseImage(completion: @escaping @MainActor (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "导入图片"
        panel.prompt = "导入"
        panel.message = "选择要放到标签上的图片"
        panel.allowedContentTypes = [.image, .pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        present(panel, completion: completion)
    }

    static func chooseLabel(completion: @escaping @MainActor (URL?) -> Void) {
        let panel = openPanel(
            title: "打开标签",
            message: "选择 P1 Label 保存的标签文件",
            prompt: "打开",
            contentTypes: [.json]
        )
        present(panel, completion: completion)
    }

    static func chooseCSV(completion: @escaping @MainActor (URL?) -> Void) {
        let panel = openPanel(
            title: "导入 CSV 批量数据",
            message: "第一行应为字段名称",
            prompt: "导入",
            contentTypes: [.commaSeparatedText, .plainText]
        )
        present(panel, completion: completion)
    }

    static func chooseSaveLocation(
        defaultName: String,
        isExportCopy: Bool,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = isExportCopy ? "导出标签副本" : "保存标签"
        panel.prompt = isExportCopy ? "导出" : "保存"
        panel.message = "标签会保存为可再次编辑的 P1 Label 文件"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(safeFilename(defaultName)).p1label.json"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        present(panel, completion: completion)
    }

    static func chooseDiagnosticReportLocation(
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "导出脱敏诊断报告"
        panel.prompt = "导出"
        panel.message = "报告不包含标签内容、文件路径、设备标识或打印数据"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "P1-Label-诊断报告.txt"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        present(panel, completion: completion)
    }

    private static func openPanel(
        title: String,
        message: String,
        prompt: String,
        contentTypes: [UTType]
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.allowedContentTypes = contentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        return panel
    }

    private static func present(
        _ panel: NSSavePanel,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow else {
            completion(panel.runModal() == .OK ? panel.url : nil)
            return
        }
        panel.beginSheetModal(for: window) { response in
            Task { @MainActor in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }

    private static func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "未命名标签" : cleaned
    }
}
