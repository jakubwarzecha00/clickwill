import SwiftUI
import ClickwillModel
import ClickwillShared

/// A screen of the Audio CD module: the disc in a drive, by its volume URL.
public enum CDPage: Hashable, Sendable {
    case disc(URL)

    public var volume: URL {
        switch self { case .disc(let volume): volume }
    }

    @MainActor public func title(in cds: AudioCDStore) -> String {
        cds.session(volume)?.title ?? ""
    }

    @MainActor public func subtitle(in cds: AudioCDStore) -> String {
        guard let session = cds.session(volume) else { return "" }
        let draft = session.draft
        guard draft.albumArtist.isEmpty else { return draft.albumArtist }
        let songs = draft.songs.count == 1 ? "1 song" : "\(draft.songs.count) songs"
        return "\(songs) · \(AudioCDScreen.time(UInt64(session.disc.duration * 1000)))"
    }
}

public struct CDScreen: View {
    @Environment(AudioCDStore.self) private var cds
    let page: CDPage

    public init(page: CDPage) {
        self.page = page
    }

    public var body: some View {
        if let session = cds.session(page.volume) {
            AudioCDScreen(session: session).id(page.volume)
        } else {
            EmptyStateView(text: "The CD Was Ejected", detail: "Insert it again to import its songs.")
        }
    }
}

/// The sidebar's Audio CD section, shown while a disc is in a drive.
public struct CDSidebarSection<Tag: Hashable>: View {
    @Environment(AudioCDStore.self) private var cds
    let tag: (CDPage) -> Tag

    public init(tag: @escaping (CDPage) -> Tag) {
        self.tag = tag
    }

    public var body: some View {
        if !cds.discs.isEmpty {
            Section("Audio CD") {
                ForEach(cds.discs) { disc in
                    Label(cds.session(disc.volume)?.title ?? disc.volumeName, systemImage: "opticaldisc")
                        .tag(tag(.disc(disc.volume)))
                        .contextMenu {
                            Button("Eject Disc") { cds.session(disc.volume)?.eject() }
                        }
                }
            }
        }
    }
}

/// What the window does after volumes are mounted or unmounted. The window gives the facts only it
/// has (an open sheet, the disc on screen) and carries the decision out.
public enum DiscChange: Equatable, Sendable {
    case show(URL)
    case showHome
    case nothing

    /// Refreshes the discs and decides. A ripping disc's session is taken before the refresh,
    /// because unmounting removes it from the store.
    @MainActor public static func after(inserted: Bool, removed: Bool, shown: URL?, sheetIsOpen: Bool,
                                        in cds: AudioCDStore) -> DiscChange {
        guard inserted || removed else { return .nothing }
        let shownSession = shown.flatMap(cds.session)
        let appeared = cds.refresh().first?.volume
        return decide(appeared: inserted ? appeared : nil, removed: removed, shown: shown,
                      shownIsRipping: shownSession?.isRipping == true,
                      shownRemains: shown.flatMap(cds.session) != nil, sheetIsOpen: sheetIsOpen)
    }

    /// An inserted disc opens its page, as in Music, unless a sheet is open or the disc on screen
    /// is being ripped. A removed disc on screen takes its page down.
    static func decide(appeared: URL?, removed: Bool, shown: URL?, shownIsRipping: Bool,
                       shownRemains: Bool, sheetIsOpen: Bool) -> DiscChange {
        if let appeared, !sheetIsOpen, !shownIsRipping { return .show(appeared) }
        if removed, shown != nil, !shownRemains { return .showHome }
        return .nothing
    }
}

/// What the disc screen asks the app to do; set by the app in `App/Clickwill/Shell/Modules.swift`.
public struct CDActions: Sendable {
    /// Ripped files go to Add Songs, so a disc gets the same duplicate check as any other album.
    public var importFiles: @MainActor @Sendable ([URL]) -> Void

    public init(importFiles: @escaping @MainActor @Sendable ([URL]) -> Void) {
        self.importFiles = importFiles
    }

    static let none = CDActions(importFiles: { _ in })
}

public extension EnvironmentValues {
    @Entry var cdActions: CDActions = .none
}
