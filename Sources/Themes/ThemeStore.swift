import Observation
import ClickwillShared

/// The theme the app's windows show.
///
/// The themes module is a plug: only the app's module list (`Modules.swift`) knows it, and
/// without it every window falls back to `AppTheme.standard`.
@MainActor
@Observable
public final class ThemeStore {
    public private(set) var current: AppTheme = .standard

    public init() {}
}
