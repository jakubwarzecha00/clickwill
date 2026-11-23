import SwiftUI
import ClickwillModel
import ClickwillShared

/// The Cover Flow screen. Its raw value is the name `--screen` takes.
public enum CoverFlowPage: String, CaseIterable, Hashable, Sendable {
    case coverFlow = "coverflow"

    public var title: String { "Cover Flow" }

    /// As many albums as the iPod shows: an album scattered across the database is one.
    @MainActor public func subtitle(in model: LibraryModel) -> String {
        "\(Self.count(model.coverFlowAlbums.count, "album")) · \(Self.count(model.trackCount, "song"))"
    }

    /// Only an iPod that has Cover Flow itself shows it.
    @MainActor public func isAvailable(in model: LibraryModel) -> Bool { model.hasCoverFlow }

    static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(number == 1 ? noun : noun + "s")"
    }
}

/// One window's Cover Flow position. It outlives the screen, so an album opened from Cover Flow
/// returns to the same place.
@MainActor
@Observable
public final class CoverFlowState {
    /// An index into `LibraryModel.coverFlowDisplay`.
    public var centered = 0

    public init() {}

    public func center(_ album: AlbumCard, in albums: [AlbumCard]) {
        if let index = albums.firstIndex(where: { $0.id == album.id }) { centered = index }
    }

    /// The arrows move by one album, Return opens the one in the middle. The window passes keys
    /// here because the focus sits on the window's scene, not on the stage.
    public func handle(_ key: KeyEquivalent, albums: [AlbumCard], open: (AlbumCard) -> Void) -> KeyPress.Result {
        switch key {
        case .leftArrow, .rightArrow:
            guard !albums.isEmpty else { return .ignored }
            let target = min(albums.count - 1, max(0, centered + (key == .leftArrow ? -1 : 1)))
            if target != centered {
                withAnimation(.spring(duration: 0.32, bounce: 0.12)) { centered = target }
            }
            return .handled
        case .return:
            guard albums.indices.contains(centered) else { return .ignored }
            open(albums[centered])
            return .handled
        default:
            return .ignored
        }
    }

    /// For looping website videos: album by album from `from` to `to` and back, one step per beat,
    /// two beats at each end. Steps follow the clock from the start, not from the previous step,
    /// so any cut one period long loops without a seam.
    public func runLoop(from: Int, to: Int) async {
        let beat = Duration.milliseconds(1200)
        let direction = to > from ? 1 : -1
        let forward = Array(stride(from: from + direction, through: to, by: direction))
        let backward = Array(stride(from: to - direction, through: from, by: -direction))
        let slots = [from] + forward + [to] + backward
        let clock = ContinuousClock()
        let start = clock.now
        // The wall-clock start lets a recorder cut whole periods without looking at the frames;
        // each period starts halfway through the pause on `from`.
        let startedAt = String(format: "%.3f", Date().timeIntervalSince1970)
        FileHandle.standardError.write(Data("coverflow-loop \(slots.count) beats of 1.2 s, started at \(startedAt)\n".utf8))
        for tick in 0... {
            try? await clock.sleep(until: start + beat * tick)
            let target = slots[tick % slots.count]
            if target != centered {
                withAnimation(.spring(duration: 0.8, bounce: 0.08)) { centered = target }
            }
        }
    }
}

public struct CoverFlowModuleScreen: View {
    let page: CoverFlowPage

    public init(page: CoverFlowPage) { self.page = page }

    public var body: some View { CoverFlowScreen() }
}

/// The Cover Flow row of the sidebar's Library section. The app gives it its selection tag.
public struct CoverFlowSidebarItem<Tag: Hashable>: View {
    @Environment(LibraryModel.self) private var model
    let tag: (CoverFlowPage) -> Tag

    public init(tag: @escaping (CoverFlowPage) -> Tag) {
        self.tag = tag
    }

    public var body: some View {
        if CoverFlowPage.coverFlow.isAvailable(in: model) {
            Label(CoverFlowPage.coverFlow.title, systemImage: "square.stack.3d.forward.dottedline")
                .tag(tag(.coverFlow))
                .disabled(model.state != .loaded)
        }
    }
}

/// What Cover Flow asks the window to do.
public struct CoverFlowActions: Sendable {
    public var openAlbum: @MainActor @Sendable (AlbumCard) -> Void
    /// Nil hides the toolbar button.
    public var reorder: (@MainActor @Sendable () -> Void)?

    public init(openAlbum: @escaping @MainActor @Sendable (AlbumCard) -> Void,
                reorder: (@MainActor @Sendable () -> Void)?) {
        self.openAlbum = openAlbum
        self.reorder = reorder
    }

    static let none = CoverFlowActions(openAlbum: { _ in }, reorder: nil)
}

public extension EnvironmentValues {
    @Entry var coverFlowActions: CoverFlowActions = .none
}
