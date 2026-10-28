import Foundation
import ITDBKit
import ClickwillModel

/// `order` - album order in the browse table. Modes, each in its own function:
///
/// - `order [--letter X]` - the order as the table laid it out;
/// - `order --check` - blocks lying outside their place in the alphabet;
/// - `order --capture` - remembering the current order as the intended one;
/// - `order --intent` - comparing the device with the remembered intent;
/// - `order --reapply [--apply]` - applying the intent again (after Music regenerated the tables);
/// - `order --repair [--apply]` - reassembling albums scattered across the table;
/// - `order --move ALBUM (--before ALBUM | --after ALBUM | --at N | --start) [--jump derived|flat] [--apply]`
///   - moving an album; the jump bar computed from the layout or flattened.
enum OrderCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let onDevice = try DeviceLibrary(reading: device, for: call)
        let library = onDevice.library
        let blocks = library.albumOrder()
        guard !blocks.isEmpty else { throw CommandError("the database has no album browse table") }
        let table = Table(onDevice: onDevice, blocks: blocks, jump: library.jumpTable(.album))

        if let name = call.value(for: "--move") { return try await move(name, in: table) }
        if call.has("--capture") {
            return capture(library, for: device, in: call.environment, jumpTable: call.value(for: "--jump") == "flat" ? .flat : .derived)
        }
        if call.has("--reapply") || call.has("--intent") { return try await compareWithIntent(table) }
        if call.has("--repair") { return try await repair(table) }
        if call.has("--check") { return check(table) }
        list(table)
    }

    /// The album browse table, loaded once per invocation.
    private struct Table {
        let onDevice: DeviceLibrary
        let blocks: [AlbumBlock]
        let jump: AlphabetJumpTable?

        var device: IPodDevice { onDevice.device }
        var library: ITLibrary { onDevice.library }
        var call: Invocation { onDevice.call }

        /// The jump bar letter under which the iPod shows the block.
        func letter(of block: AlbumBlock) -> String {
            jump?.section(containing: block.range.lowerBound)?.character.map(String.init) ?? "?"
        }
    }

    private static func move(_ name: String, in table: Table) async throws {
        let (library, blocks) = (table.library, table.blocks)
        let target: AlbumOrderTarget
        if let other = table.call.value(for: "--before") { target = .before(other) }
        else if let other = table.call.value(for: "--after") { target = .after(other) }
        else if table.call.has("--start") { target = .startOfLetter }
        else if let at = table.call.value(for: "--at").flatMap(Int.init) { target = .atIndex(at) }
        else { throw CommandError("give --before ALBUM, --after ALBUM, --at N or --start") }

        let policy: JumpTablePolicy = table.call.value(for: "--jump") == "flat" ? .flat : .derived

        guard let moved = blocks.first(where: { $0.album == name }) else {
            throw CommandError("the table has no album '\(name)'")
        }
        let updated = try library.movingAlbum(name, target, jumpTable: policy)
        let after = updated.albumOrder()
        guard let landed = after.first(where: { $0.album == name }) else {
            throw CommandError("the block disappeared after the move - change rejected")
        }
        let neighbours = after.filter { abs($0.id - landed.id) <= 1 }

        var jumpNote = "no bar"
        if let rebuilt = updated.jumpTable(.album) {
            let describe = rebuilt.entries.map {
                "\($0.character.map(String.init) ?? "0x\(String($0.letter, radix: 16))")+\($0.count)"
            }
            jumpNote = (rebuilt.lettersAreContiguous ? "letters contiguous" : "LETTERS REPEATED")
                + ", \(rebuilt.entries.count) entries: " + describe.joined(separator: " ")
        }

        report("Moving an album", [
            ("album", "\(name)  (\(moved.trackCount) tracks)"),
            ("letter", table.letter(of: moved)),
            ("now", "position \(moved.id) of \(blocks.count), slots \(moved.range.lowerBound)-\(moved.range.upperBound - 1)"),
            ("after the change", "position \(landed.id), slots \(landed.range.lowerBound)-\(landed.range.upperBound - 1)"),
            ("neighbors", neighbours.map(\.album).joined(separator: " | ")),
            ("jump bar", jumpNote),
        ])

        guard table.call.has("--apply") else {
            print("\n  That was a preview. To write: add --apply")
            return
        }
        announce(try await table.onDevice.write(updated, note: "order: album '\(name)' to position \(landed.id)",
                                            jumpTable: policy))
    }

    /// `--intent` compares, `--reapply` also applies the intent to the device.
    private static func compareWithIntent(_ table: Table) async throws {
        let (device, library) = (table.device, table.library)
        let store = try table.call.environment.orderIntents()
        guard let intent = try store.load(deviceGUID: device.identity) else {
            print("No saved intent for this device. Capture one: order --capture")
            return
        }
        let (updated, outcome) = try library.applyingOrderIntent(intent)
        report("Intended order", [
            ("captured", intent.capturedAt.formatted(date: .abbreviated, time: .shortened)),
            ("albums in the intent", "\(intent.albums.count)"),
            ("jump bar", intent.jumpTable.rawValue),
            ("device", outcome.changed ? "DIFFERS from the intent" : "matches the intent"),
            ("new albums", outcome.newAlbums.isEmpty ? "0" : outcome.newAlbums.joined(separator: ", ")),
            ("missing albums", outcome.missingAlbums.isEmpty ? "0" : outcome.missingAlbums.joined(separator: ", ")),
            ("new / missing tracks", "\(outcome.newTracks) / \(outcome.missingTracks)"),
        ])
        guard table.call.has("--reapply"), outcome.changed else { return }
        guard table.call.has("--apply") else {
            print("\n  That was a preview. To apply the intent to the device: add --apply")
            return
        }
        announce(try await table.onDevice.write(updated, note: "reapplying the intended order",
                                            jumpTable: intent.jumpTable))
    }

    private static func repair(_ table: Table) async throws {
        let library = table.library
        let plan = try library.planAlbumOrderRepair()
        guard !plan.isEmpty else {
            print("The album browse table needs no repair.")
            return
        }
        report("Browse table repair", [
            ("albums", "\(plan.moves.count)"),
            ("positions to change", "\(plan.changedPositions)"),
        ])
        print("")
        for move in plan.moves {
            let from = move.from.map { "\($0.lowerBound)-\($0.upperBound - 1)" }.joined(separator: ", ")
            let to = "\(move.to.lowerBound)-\(move.to.upperBound - 1)"
            let letter = move.letter.map(String.init) ?? "?"
            let state = move.isNoop ? "unchanged" : "\(from)  ->  \(to)"
            print("  [\(letter)] \(move.album)  (\(move.trackCount) tracks)")
            print("      slots \(state)")
        }

        guard table.call.has("--apply") else {
            print("\n  That was a preview. To write: add --apply")
            return
        }
        let updated = try library.applyingAlbumOrderRepair(plan)
        let after = updated.albumOrder()
        let stillSplit = Dictionary(grouping: after, by: \.album).filter { $0.value.count > 1 }
        guard stillSplit.isEmpty else {
            throw CommandError("after the repair there are still albums in several blocks: \(stillSplit.keys.sorted().joined(separator: ", "))")
        }
        announce(try await table.onDevice.write(updated, note: "browse table repair: \(plan.moves.count) albums"))
    }

    /// A block lies outside its place if its sort key is smaller
    /// than the key of the previous block. The table should be non-decreasing.
    private static func check(_ table: Table) {
        let (library, blocks) = (table.library, table.blocks)
        let byIndex = Dictionary(uniqueKeysWithValues: library.tracks.enumerated().map { ($0.offset, $0.element) })
        func key(_ block: AlbumBlock) -> String {
            let track = byIndex[block.trackIndices[0]]
            let raw = track?.sortAlbum ?? track?.album ?? ""
            return raw.lowercased()
        }
        var broken: [(AlbumBlock, AlbumBlock)] = []
        for pair in zip(blocks, blocks.dropFirst()) where key(pair.1) < key(pair.0) {
            broken.append(pair)
        }
        let split = Dictionary(grouping: blocks, by: \.album).filter { $0.value.count > 1 }

        // The bar computed from the layout must reproduce the one iTunes wrote -
        // this checks whether our letter function agrees with theirs.
        var jumpVerdict = "no bar"
        if let stored = library.jumpTable(.album) {
            let derived = stored.rebuilt(fromRuns: blocks.map { (library.albumLetterCode($0), $0.trackCount) })
            if derived.mhod().rawBody == stored.mhod().rawBody {
                jumpVerdict = "identical byte for byte to the one written by iTunes"
            } else {
                let storedDesc = stored.entries.map { "\($0.character.map(String.init) ?? "0x\(String($0.letter, radix: 16))")+\($0.count)" }
                let derivedDesc = derived.entries.map { "\($0.character.map(String.init) ?? "0x\(String($0.letter, radix: 16))")+\($0.count)" }
                jumpVerdict = "DIFFERENT\n      iTunes: \(storedDesc.joined(separator: " "))\n      ours:   \(derivedDesc.joined(separator: " "))"
            }
        }
        report("Album browse table", [
            ("entries", "\(library.browseIndex(.album)?.entries.count ?? 0)"),
            ("blocks", "\(blocks.count)"),
            ("albums in several blocks", "\(split.count)"),
            ("broken alphabet boundaries", "\(broken.count)"),
            ("jump bar from the layout", jumpVerdict),
        ])
        if !split.isEmpty {
            print("\n  Albums split across several places in the table:")
            for (name, parts) in split.sorted(by: { $0.key < $1.key }) {
                let where_ = parts.map { "slot \($0.range.lowerBound) (\($0.trackCount) tracks, letter \(table.letter(of: $0)))" }
                print("    \(name)")
                for part in where_ { print("      \(part)") }
            }
        }
        if !broken.isEmpty {
            print("\n  Places where the order breaks the alphabet:")
            for (previous, current) in broken {
                print("    slot \(current.range.lowerBound): after '\(previous.album)' comes '\(current.album)' (\(current.trackCount) tracks)")
            }
        }
    }

    /// Remembers the current order as the intended one - only on the Mac, does not touch the iPod.
    private static func capture(_ library: ITLibrary, for device: IPodDevice, in environment: LibraryEnvironment,
                                jumpTable: JumpTablePolicy) {
        do {
            let store = try environment.orderIntents()
            try store.save(library.captureOrderIntent(jumpTable: jumpTable), deviceGUID: device.identity)
            print("  Order intent saved: \(store.url(forDevice: device.identity).path)")
        } catch {
            print("  WARNING: the order intent could not be saved: \(error)")
        }
    }

    private static func list(_ table: Table) {
        let wanted = table.call.value(for: "--letter")?.uppercased()
        var shown = 0
        for block in table.blocks {
            let mark = table.letter(of: block)
            if let wanted, mark != wanted { continue }
            if shown == 0 { print("Album order as the browse table laid it out\n") }
            let position = String(block.id).padding(toLength: 4, withPad: " ", startingAt: 0)
            let title = block.album.isEmpty ? "(no album)" : block.album
            print("  \(position) [\(mark)]  \(title)  -  \(block.trackCount) tracks")
            shown += 1
        }
        if shown == 0 { print("No blocks for the letter \(wanted ?? "?")") }
    }
}
