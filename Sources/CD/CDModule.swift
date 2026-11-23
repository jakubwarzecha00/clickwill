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
