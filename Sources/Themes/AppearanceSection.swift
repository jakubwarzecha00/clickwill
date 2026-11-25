import SwiftUI

/// The Appearance section at the top of Settings.
public struct AppearanceSection: View {
    @Bindable private var store: ThemeStore

    public init(store: ThemeStore) {
        self.store = store
    }

    public var body: some View {
        Section {
            Picker("Appearance", selection: $store.choice) {
                ForEach(ThemeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("With System, Clickwill turns light or dark together with your Mac.")
        }
    }
}
