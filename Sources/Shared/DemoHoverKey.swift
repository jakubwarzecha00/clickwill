import SwiftUI

public extension EnvironmentValues {
    /// The element over which a website recording fakes the cursor; `nil` outside a recording.
    /// The app sets it from the recording tool's notification (`DemoHover`).
    @Entry var demoHover: String? = nil
}
