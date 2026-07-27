import AppKit
import SwiftUI

/// A narrow responder-chain bridge. SwiftUI owns the object and selection;
/// this transparent AppKit view makes mouse click counts and arrow-key focus
/// deterministic on macOS.
struct CanvasLayerInputCapture: NSViewRepresentable {
    let normalStep: Double
    let onSingleClick: (Bool) -> Void
    let onDoubleClick: () -> Void
    let onMove: (Double, Double) -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.normalStep = normalStep
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        view.onMove = onMove
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.normalStep = normalStep
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        view.onMove = onMove
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
    }

    final class KeyView: NSView {
        var normalStep = 0.1
        var onSingleClick: ((Bool) -> Void)?
        var onDoubleClick: (() -> Void)?
        var onMove: ((Double, Double) -> Void)?
        var onDrag: ((CGSize) -> Void)?
        var onDragEnded: (() -> Void)?
        // Keep the origin in window coordinates. The represented view moves as
        // its layer is dragged; a local-coordinate origin would move with it
        // and feed an opposing translation back into the drag on every frame.
        private var mouseDownPointInWindow: NSPoint?

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            mouseDownPointInWindow = event.locationInWindow
            if event.clickCount >= 2 {
                onDoubleClick?()
            } else {
                onSingleClick?(event.modifierFlags.contains(.shift))
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownPointInWindow else { return }
            let point = event.locationInWindow
            onDrag?(CGSize(
                width: point.x - mouseDownPointInWindow.x,
                height: mouseDownPointInWindow.y - point.y
            ))
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownPointInWindow = nil
            onDragEnded?()
        }

        override func keyDown(with event: NSEvent) {
            let step = event.modifierFlags.contains(.shift) ? 1.0 : normalStep
            switch event.keyCode {
            case 123: onMove?(-step, 0) // left
            case 124: onMove?(step, 0)  // right
            case 125: onMove?(0, step)  // down
            case 126: onMove?(0, -step) // up
            default: super.keyDown(with: event)
            }
        }
    }
}
