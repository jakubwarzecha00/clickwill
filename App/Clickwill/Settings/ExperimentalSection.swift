import SwiftUI
import ClickwillModel

/// Settings › Experimental iPods: the switch, the allowed devices, and Developer Mode
/// (after a warning, `ExperimentalConsent.askDeveloperMode`). Technical wording, without the first person.
struct ExperimentalSection: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var permissions = model.permissions
        Section {
            Toggle("Allow writing to unconfirmed iPod models", isOn: $permissions.isEnabled)
            ForEach(permissions.grants) { grant in
                LabeledContent {
                    Button("Revoke", role: .destructive) {
                        Task { await model.revokeExperimentalWriting(identity: grant.identity) }
                    }
                } label: {
                    Text(grant.modelName)
                    Text("Allowed \(grant.allowedAt.formatted(date: .abbreviated, time: .omitted)) · firmware \(grant.firmwareVersion ?? "not reported")")
                }
            }
            Toggle("Developer Mode", isOn: Binding(
                get: { permissions.developerMode },
                set: { on in permissions.developerMode = on ? ExperimentalConsent.askDeveloperMode() : false }))
                .disabled(!permissions.isEnabled)
        } header: {
            Text("Experimental iPods")
        } footer: {
            Text(footer)
        }
        .onChange(of: permissions.isEnabled) { Task { await model.reapplyWritePolicy() } }
        .onChange(of: permissions.developerMode) { Task { await model.reapplyWritePolicy() } }
    }

    private var footer: String {
        """
        Shows “Allow Experimental Writing…” in Diagnostics when all required checks pass \
        on an iPod with an unsigned database. Permission is per device and lapses on a firmware change. \
        Turning this off revokes all permissions and ends Developer Mode.

        Developer Mode, for developers measuring a new model: writing to any unsigned database, disk images included, \
        without the family list, the USB confirmation or the list of measured artwork formats. \
        The signature, identity conflicts and the backup before every write stay. Ends when Clickwill quits.
        """
    }
}
