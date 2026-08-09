import Foundation

struct PendingPrint: Identifiable, Sendable {
    enum Source: Sendable, Equatable {
        case calibration
        case paperCalibration
        case document
        case history
    }

    let id = UUID()
    let data: Data
    let name: String
    let source: Source
}

enum LayerAlignment {
    case left
    case horizontalCenter
    case right
    case top
    case verticalCenter
    case bottom
}
