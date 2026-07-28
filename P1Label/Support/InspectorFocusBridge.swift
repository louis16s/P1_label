import AppKit
import SwiftUI

/// Ends text editing when the user clicks the non-control background of the
/// inspector. SwiftUI `Form` does not expose a reliable blank-area focus hook
/// on macOS, so this bridge stays limited to responder-chain coordination.
struct InspectorFocusBridge: NSViewRepresentable {
    nonisolated static let monitoredEvents: NSEvent.EventTypeMask = .leftMouseUp

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        context.coordinator.observeClicks(inside: view)
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {}

    static func dismantleNSView(_ nsView: TrackingView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class TrackingView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    final class Coordinator {
        private var eventMonitor: Any?

        func observeClicks(inside trackingView: TrackingView) {
            stopObserving()
            // Wait until AppKit has completed NSTextView's mouse tracking.
            // Resigning first responder from a mouse-down monitor can interrupt
            // TextKit's selection loop and leave the main thread unresponsive.
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: InspectorFocusBridge.monitoredEvents) {
                [weak trackingView] event in
                let locationInWindow = event.locationInWindow
                let windowNumber = event.windowNumber
                DispatchQueue.main.async { [weak trackingView] in
                    guard let trackingView,
                          let window = trackingView.window,
                          window.windowNumber == windowNumber,
                          trackingView.bounds.contains(
                              trackingView.convert(locationInWindow, from: nil)
                          ),
                          let contentView = window.contentView
                    else {
                        return
                    }

                    let point = contentView.convert(locationInWindow, from: nil)
                    let clickedView = contentView.hitTest(point)
                    guard !Self.isControlOrTextEditor(clickedView) else { return }

                    window.makeFirstResponder(nil)
                }
                return event
            }
        }

        func stopObserving() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        deinit {
            stopObserving()
        }

        @MainActor
        private static func isControlOrTextEditor(_ view: NSView?) -> Bool {
            var candidate = view
            while let current = candidate {
                if current is NSControl || current is NSTextView {
                    return true
                }
                candidate = current.superview
            }
            return false
        }
    }
}
