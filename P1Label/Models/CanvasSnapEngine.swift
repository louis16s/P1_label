import Foundation

struct CanvasGuideState: Equatable, Sendable {
    var verticalMM: Double?
    var horizontalMM: Double?

    static let none = CanvasGuideState()
}

struct CanvasSnapResult: Equatable, Sendable {
    let x: Double
    let y: Double
    let guides: CanvasGuideState
}

struct CanvasSnapTargets: Sendable {
    let horizontal: [Double]
    let vertical: [Double]

    static func make(
        paper: PaperSize,
        layers: [LabelLayer],
        excluding layerID: UUID
    ) -> CanvasSnapTargets {
        var horizontal = [0, paper.widthMM / 2, paper.widthMM]
        var vertical = [0, paper.heightMM / 2, paper.heightMM]
        for layer in layers where layer.id != layerID && !layer.isHidden {
            horizontal.append(contentsOf: [layer.x, layer.x + layer.width / 2, layer.x + layer.width])
            vertical.append(contentsOf: [layer.y, layer.y + layer.height / 2, layer.y + layer.height])
        }
        return CanvasSnapTargets(
            horizontal: Self.sortedUnique(horizontal),
            vertical: Self.sortedUnique(vertical)
        )
    }

    func snap(
        x proposedX: Double,
        y proposedY: Double,
        layerSize: CGSize,
        paper: PaperSize,
        threshold: Double = 0.3,
        gridStep: Double? = 0.5
    ) -> CanvasSnapResult {
        let maximumX = max(0, paper.widthMM - layerSize.width)
        let maximumY = max(0, paper.heightMM - layerSize.height)
        let clampedX = min(max(0, proposedX), maximumX)
        let clampedY = min(max(0, proposedY), maximumY)
        let xMatch = bestMatch(
            origin: clampedX,
            length: layerSize.width,
            targets: horizontal,
            threshold: threshold
        )
        let yMatch = bestMatch(
            origin: clampedY,
            length: layerSize.height,
            targets: vertical,
            threshold: threshold
        )
        let x = min(max(0, xMatch?.origin ?? grid(clampedX, step: gridStep)), maximumX)
        let y = min(max(0, yMatch?.origin ?? grid(clampedY, step: gridStep)), maximumY)
        return CanvasSnapResult(
            x: x,
            y: y,
            guides: CanvasGuideState(
                verticalMM: xMatch?.target,
                horizontalMM: yMatch?.target
            )
        )
    }

    private func bestMatch(
        origin: Double,
        length: Double,
        targets: [Double],
        threshold: Double
    ) -> (origin: Double, target: Double)? {
        let anchors = [origin, origin + length / 2, origin + length]
        var result: (origin: Double, target: Double, distance: Double)?
        for (index, anchor) in anchors.enumerated() {
            guard let target = Self.nearest(to: anchor, in: targets) else { continue }
            let distance = abs(target - anchor)
            guard distance <= threshold else { continue }
            if let result, distance >= result.distance { continue }
            let anchorOffset = index == 0 ? 0 : (index == 1 ? length / 2 : length)
            result = (target - anchorOffset, target, distance)
        }
        return result.map { ($0.origin, $0.target) }
    }

    private func grid(_ value: Double, step: Double?) -> Double {
        guard let step, step > 0 else { return value }
        return (value / step).rounded() * step
    }

    private static func sortedUnique(_ values: [Double]) -> [Double] {
        Array(Set(values.filter(\.isFinite))).sorted()
    }

    private static func nearest(to value: Double, in sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let insertion = sorted.partitioningIndex { $0 >= value }
        if insertion == 0 { return sorted[0] }
        if insertion == sorted.count { return sorted[sorted.count - 1] }
        let lower = sorted[insertion - 1]
        let upper = sorted[insertion]
        return abs(value - lower) <= abs(upper - value) ? lower : upper
    }
}

private extension Array {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Int {
        var lower = 0
        var upper = count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if predicate(self[middle]) {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return lower
    }
}
