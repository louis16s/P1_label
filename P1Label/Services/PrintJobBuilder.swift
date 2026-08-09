import Foundation
import OSLog

enum PrintJobBuilderError: LocalizedError {
    case jobTooLarge

    var errorDescription: String? {
        switch self {
        case .jobTooLarge:
            "批量打印任务过大，请减少记录数量或打印份数后重试"
        }
    }
}

struct PrintJobSettings: Sendable {
    let horizontalOffsetMM: Double
    let verticalOffsetMM: Double
    let copies: Int
    let inverted: Bool
    let paperMode: P1PaperMode
    let gapLengthMM: Int
    let darkness: Int
    let speed: Int

    func withCopies(_ copies: Int) -> PrintJobSettings {
        PrintJobSettings(
            horizontalOffsetMM: horizontalOffsetMM,
            verticalOffsetMM: verticalOffsetMM,
            copies: copies,
            inverted: inverted,
            paperMode: paperMode,
            gapLengthMM: gapLengthMM,
            darkness: darkness,
            speed: speed
        )
    }
}

enum PrintJobBuilder {
    nonisolated static let maximumJobBytes = 256 * 1_024 * 1_024

    private static let logger = Logger(
        subsystem: "com.louis.p1label",
        category: "PrintPreparation"
    )

    static func documentData(
        document: LabelDocument,
        settings: PrintJobSettings
    ) async throws -> Data {
        let worker = Task.detached(priority: .userInitiated) {
            let clock = ContinuousClock()
            let start = clock.now
            let raster = try LabelRasterizer.raster(
                document: document,
                horizontalOffsetMM: settings.horizontalOffsetMM,
                verticalOffsetMM: settings.verticalOffsetMM
            )
            try Task.checkCancellation()
            let data = repeatedPrintData(for: raster, settings: settings)
            let duration = start.duration(to: clock.now)
            logger.info(
                "Prepared document job: \(data.count, privacy: .public) bytes in \(String(describing: duration), privacy: .public)"
            )
            return data
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func batchData(
        document: LabelDocument,
        records: [[String: String]],
        settings: PrintJobSettings
    ) async throws -> Data {
        let worker = Task.detached(priority: .userInitiated) {
            let clock = ContinuousClock()
            let start = clock.now
            var result = Data()
            for (recordIndex, record) in records.enumerated() {
                try Task.checkCancellation()
                var renderedDocument = document
                for index in renderedDocument.layers.indices {
                    for (key, value) in record {
                        renderedDocument.layers[index].text = renderedDocument.layers[index].text
                            .replacingOccurrences(of: "{{\(key)}}", with: value)
                    }
                }
                let raster = try LabelRasterizer.raster(
                    document: renderedDocument,
                    horizontalOffsetMM: settings.horizontalOffsetMM,
                    verticalOffsetMM: settings.verticalOffsetMM
                )
                let recordData = repeatedPrintData(for: raster, settings: settings)
                if recordIndex == 0 {
                    let estimatedSize = try estimatedBatchSize(
                        recordBytes: recordData.count,
                        recordCount: records.count
                    )
                    result.reserveCapacity(estimatedSize)
                }
                result.append(recordData)
            }
            let duration = start.duration(to: clock.now)
            logger.info(
                "Prepared batch job: \(records.count, privacy: .public) labels, \(result.count, privacy: .public) bytes in \(String(describing: duration), privacy: .public)"
            )
            return result
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func repeatedPrintData(
        for raster: P1Raster,
        settings: PrintJobSettings
    ) -> Data {
        let printableRaster = settings.inverted ? raster.inverted() : raster
        let oneJob = P1Protocol.printJob(
            raster: printableRaster,
            paperMode: settings.paperMode,
            gapLengthMM: settings.gapLengthMM,
            darkness: settings.darkness,
            speed: settings.speed
        )
        let copies = min(99, max(1, settings.copies))
        var result = Data()
        result.reserveCapacity(oneJob.count * copies)
        for _ in 0..<copies {
            result.append(oneJob)
        }
        return result
    }

    static func estimatedBatchSize(
        recordBytes: Int,
        recordCount: Int
    ) throws -> Int {
        let size = max(0, recordBytes).multipliedReportingOverflow(
            by: max(0, recordCount)
        )
        guard !size.overflow, size.partialValue <= maximumJobBytes else {
            throw PrintJobBuilderError.jobTooLarge
        }
        return size.partialValue
    }
}
