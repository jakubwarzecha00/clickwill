import Foundation

extension Array {
    /// The same semantics as `move(fromOffsets:toOffset:)` from SwiftUI - kept
    /// here so the model does not depend on SwiftUI and can be tested on its own.
    mutating func moving(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moved = source.map { self[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { remove(at: index) }
        insert(contentsOf: moved, at: destination - before)
    }
}
