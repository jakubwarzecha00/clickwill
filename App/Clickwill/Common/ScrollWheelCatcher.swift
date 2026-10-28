import SwiftUI
import AppKit

/// Captures scrolling with the mouse wheel and the trackpad. SwiftUI offers no API for this,
/// and in Cover Flow and on the Albums wheel it is the main way of navigating.
struct ScrollWheelCatcher: NSViewRepresentable {
    /// A vertical list (the Albums wheel): only vertical movement counts, and scrolling
    /// the content up - as in any list - leads to the next album.
    /// Otherwise (Cover Flow) - the stronger axis, with the sign as given by the system.
    var vertical = false
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.vertical = vertical
        view.onStep = onStep
        return view
    }
    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.vertical = vertical
        nsView.onStep = onStep
    }

    final class CatcherView: NSView {
        var vertical = false
        var onStep: ((Int) -> Void)?
        private var accumulated: CGFloat = 0
        private var monitor: Any?

        // The view is transparent to clicks - they go to the artwork underneath -
        // and scrolling is caught through a local event monitor, because without a hit test
        // AppKit would not deliver it here.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var acceptsFirstResponder: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window == self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                self.handle(event)
                return nil
            }
        }

        // The monitor goes away with the view leaving the window (viewDidMoveToWindow with window == nil),
        // so deinit has nothing to clean up - and from MainActor isolation it could not anyway.

        private func handle(_ event: NSEvent) {
            let delta = vertical ? -event.scrollingDeltaY
                : abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            accumulated += event.hasPreciseScrollingDeltas ? delta : delta * 12
            let threshold: CGFloat = 40
            while accumulated >= threshold { accumulated -= threshold; onStep?(1) }
            while accumulated <= -threshold { accumulated += threshold; onStep?(-1) }
            if event.phase == .ended || event.momentumPhase == .ended { accumulated = 0 }
        }
    }
}
