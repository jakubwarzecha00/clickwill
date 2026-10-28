import SwiftUI
import ClickwillModel
import ITDBKit

/// The iPod card above the sidebar: the name, model, used and free space,
/// choosing an iPod (with two or more) and ejecting. A system fill,
/// separate above the list - the iPod is the starting point, not one of the navigation
/// items.
struct DeviceCard: View {
    @Environment(LibraryModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @Environment(WindowState.self) private var window
    /// The first row of the sidebar list (macOS 14-25, `SidebarView.cardInList`):
    /// the side insets then come from the list itself.
    var inList = false
    /// The popover with connected iPods.
    @State private var showPicker = false

    var body: some View {
        let device = model.device
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                // With two or more iPods the symbol and the name open the chooser
                // popover; the arrow stands next to the name, far from Eject - next to
                // each other they provoked an eject instead of a choice.
                if model.connectedChoices.count > 1 {
                    Button {
                        model.refreshConnectedChoices(force: true)
                        showPicker.toggle()
                    } label: {
                        identity(device, chooser: true).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Choose an iPod. \(model.connectedChoices.count) are connected.")
                    .accessibilityLabel("Choose iPod")
                    .accessibilityValue(model.currentChoice?.name ?? "")
                    .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                        IPodPicker(choices: model.connectedChoices, currentID: model.currentChoice?.id) { choice in
                            showPicker = false
                            choose(choice)
                        }
                    }
                    .animation(.smooth(duration: 0.2), value: showPicker)
                } else {
                    identity(device, chooser: false)
                }
                Spacer(minLength: 12)
                if device != nil || !model.demoChoices.isEmpty { ejectButton(device) }
            }
            // `--demo-ipod`: the card as with a real iPod, with used space.
            if device == nil, !model.demoChoices.isEmpty, let choice = model.currentChoice {
                capacityBar(used: choice.usedCapacity, total: choice.totalCapacity, free: choice.availableCapacity)
            }
            if let device {
                capacityBar(used: device.volume.usedCapacity, total: device.volume.totalCapacity,
                            free: device.volume.availableCapacity)
                // A device whose format we have not confirmed on hardware
                // must say so plainly - a silent block looks like a failure.
                if !device.supportsWriting {
                    Label("Read-only. \(ErrorPresenter.readOnlyMessage(device.readOnlyReason))", systemImage: "lock.fill")
                        .font(.theme(.fine))
                        .foregroundStyle(Theme.warn)
                        // Without fixedSize: while measuring the window's minimum height
                        // the bar gets almost zero width, the text broke after
                        // every letter and pushed the window to 2000 pt - the player
                        // and the top of the bar fell off the screen (seen on a nano 2G).
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(11)
        // A system fill, not glass: the sidebar itself is glass, and the HIG
        // advises against glass on glass.
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        .padding(EdgeInsets(top: 6, leading: inList ? 0 : 10, bottom: 8, trailing: inList ? 0 : 10))
        .alert("Switch to \u{201C}\(window.switchCandidate?.name ?? "")\u{201D}?",
               isPresented: Binding(get: { window.switchCandidate != nil },
                                    set: { if !$0 { window.closeModal(); window.modalDidClose() } }),
               presenting: window.switchCandidate) { choice in
            Button("Discard Changes and Switch", role: .destructive) { switchTo(choice) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            let count = model.changes.log.count
            Text("\(count) \(count == 1 ? "change hasn't" : "changes haven't") been written to \u{201C}\(model.currentChoice?.name ?? "this iPod")\u{201D}. If you switch, \(count == 1 ? "it" : "they") will be discarded.")
        }
    }

    /// The symbol, name and model - the left part of the card. `chooser`: an arrow next to
    /// the name, as in a button with a list.
    private func identity(_ device: IPodDevice?, chooser: Bool) -> some View {
        HStack(spacing: 10) {
            graphic.frame(width: 22, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 6) {
                    // Up to two lines: names given to iPods can be long ("Anna's iPod nano 2").
                    Text(model.deviceName ?? model.currentChoice?.name ?? model.source?.displayName ?? "No iPod connected")
                        .font(.theme(.row, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if chooser {
                        Image(systemName: "chevron.down")
                            .font(.symbol(.tiny, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showPicker ? 180 : 0))
                            .frame(width: 17, height: 17)
                            .background(.fill.tertiary, in: .circle)
                    }
                }
                Text(detail).font(.theme(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    /// The drawing of the loaded iPod; without an iPod - a generic shape, dimmed.
    @ViewBuilder private var graphic: some View {
        if let device = model.device {
            IPodGraphic(device: device)
        } else if let choice = model.currentChoice {
            IPodGraphic(choice: choice)
        } else {
            IPodGraphic(shape: .generic, finish: nil).opacity(model.source == nil ? 0.35 : 1)
        }
    }

    private func capacityBar(used: Int64, total: Int64, free: Int64) -> some View {
        VStack(spacing: 5) {
            ProgressView(value: Double(used), total: Double(max(1, total)))
                .progressViewStyle(.linear)
                .controlSize(.small)
            HStack {
                Text("\(used.gigabytes) used")
                Spacer()
                Text("\(free.gigabytes) free")
            }
            .font(.theme(.small)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    /// Choosing another iPod. Unsaved changes belong to the current one - before
    /// loading the second one we ask whether to discard them.
    private func choose(_ choice: IPodChoice) {
        guard choice.source != model.source else { return }
        if model.hasPendingChanges { window.confirmSwitch(to: choice) } else { switchTo(choice) }
    }

    private func switchTo(_ choice: IPodChoice) {
        // We play from a file on the current iPod - after switching there would be nowhere to play it from.
        playback.stop()
        window.showHome(animated: true)
        Task { await model.load(choice.source) }
    }

    /// Ejecting. The iPod reads the database only on eject, so this is not
    /// mere politeness toward the file system - without it the device shows
    /// the state from before the write, and it looks like a failed write.
    /// Without a device (`--demo-ipod`) the button just stands in its place.
    private func ejectButton(_ device: IPodDevice?) -> some View {
        Button {
            guard let device else { return }
            // First we let go of the file we play from the iPod. Without this our own
            // player holds the volume and the eject fails with error -47.
            playback.stop()
            switch DeviceEject.run(mountPoint: device.volume.mountPoint, pendingChanges: model.changes.log.count) {
            case .ejected, .cancelled: break
            case .failed(let reason): DeviceEject.report(reason)
            }
        } label: {
            Image(systemName: "eject.fill")
        }
        .buttonStyle(.borderless)
        .help("Eject the iPod. It loads your changes as it disconnects.")
    }

    /// Three states, not two: a device, a backup from disk and nothing.
    private var detail: String {
        // The model comes from the device, not from an assumption - a hard-coded
        // "iPod classic" would be false on every other iPod.
        if let device = model.device {
            // The generation from the catalog, when it agrees with the device.
            // On the card, short ("iPod nano") - the full generation name is in the popover and in Overview.
            let name = device.catalogEntry?.generation.familyName ?? device.model.name + (device.model.isConfirmed ? "" : "?")
            // Without capacity: it stands right below on the usage bar, and here it cut the description short.
            return name
        }
        if case .snapshot = model.source {
            if let choice = model.currentChoice, !model.demoChoices.isEmpty {
                return "\(choice.generation?.familyName ?? choice.modelName) · \(choice.totalCapacity.gigabytes)"
            }
            return model.demoDeviceDetail ?? "snapshot from disk"
        }
        return "connect one to get started"
    }
}
