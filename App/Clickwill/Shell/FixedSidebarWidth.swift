import SwiftUI
import AppKit

extension View {
    /// A `NavigationSplitView` sidebar with a fixed width: no dragging of the
    /// edge, no collapsing and no resize cursor (every width
    /// change shifted the whole scene sideways).
    /// Call it on the sidebar view.
    func fixedSidebarWidth(_ width: CGFloat) -> some View {
        navigationSplitViewColumnWidth(width)
            .background(SidebarWidthLock(width: width))
    }
}

/// The column width alone is only a suggestion in SwiftUI on macOS: the edge can
/// still be dragged, and on every update SwiftUI restores its own
/// sidebar limits (min 140 pt, no maximum, collapsing enabled - as read
/// from AppKit). So the lock lives in AppKit, on the sidebar's split item
/// (`NSSplitViewItem`): minimum and maximum thickness equal to the width, no
/// collapsing. Observing these three values restores them right away whenever SwiftUI
/// changes them.
private struct SidebarWidthLock: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> NSView { LockView(width: width) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// An invisible view in the sidebar - from it we reach the window's split.
    private final class LockView: NSView {
        let width: CGFloat
        private weak var item: NSSplitViewItem?
        private var observations: [NSKeyValueObservation] = []

        init(width: CGFloat) {
            self.width = width
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations = []
            guard let item = sidebarItem() else { return }
            self.item = item
            lock()
            observations = [watch(\.minimumThickness), watch(\.maximumThickness), watch(\.canCollapse)]
        }

        /// The sidebar's split item: the first in the controller that
        /// SwiftUI sets as the delegate of the window's `NSSplitView`.
        private func sidebarItem() -> NSSplitViewItem? {
            var view = superview
            while let current = view, !(current is NSSplitView) { view = current.superview }
            return ((view as? NSSplitView)?.delegate as? NSSplitViewController)?.splitViewItems.first
        }

        /// AppKit changes these values on the main thread, so the notification arrives on it too.
        private func watch<Value>(_ key: KeyPath<NSSplitViewItem, Value>) -> NSKeyValueObservation {
            guard let item else { preconditionFailure("watch() before the sidebar was found") }
            return item.observe(key) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.lock() }
            }
        }

        private func lock() {
            guard let item else { return }
            if item.minimumThickness != width { item.minimumThickness = width }
            if item.maximumThickness != width { item.maximumThickness = width }
            if item.canCollapse { item.canCollapse = false }
        }
    }
}
