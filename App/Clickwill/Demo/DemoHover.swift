import SwiftUI
import Observation

/// A faked mouse hover in website recordings. The recording tool
/// posts the notification "clickwill.demo.hover" with the name of
/// an element or an empty string. The window passes it to the views as `\.demoHover`,
/// so a view knows nothing about recordings - it only asks whether to fake a hover.
@MainActor @Observable
final class DemoHover {
    static let notification = Notification.Name("clickwill.demo.hover")

    private(set) var target: String?

    /// Listens only in demo mode (`--demo`); in a normal launch it does nothing.
    init(listening: Bool) {
        guard listening else { return }
        DistributedNotificationCenter.default().addObserver(forName: Self.notification, object: nil, queue: .main) { [weak self] note in
            let name = note.object as? String
            MainActor.assumeIsolated { self?.target = name?.isEmpty == false ? name : nil }
        }
    }
}

struct DemoHoverKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// The element over which a recording fakes the cursor (`DemoHover`); outside a recording `nil`.
    var demoHover: String? {
        get { self[DemoHoverKey.self] }
        set { self[DemoHoverKey.self] = newValue }
    }
}
