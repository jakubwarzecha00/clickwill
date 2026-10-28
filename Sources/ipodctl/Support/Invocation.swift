import Foundation
import ClickwillModel

/// One command invocation: the arguments and the environment it runs in.
///
/// A command gets them as a value instead of reading the global `CommandLine` and
/// ending the process - so it can be called from a test on a fake iPod,
/// with backups in a temporary folder.
struct Invocation {
    /// Arguments without the program name; the first is the command.
    let arguments: [String]
    /// Where the backups and the order intent are, whether Music is running.
    var environment: LibraryEnvironment = .standard

    var command: String? { arguments.first }

    /// Whether a flag was given, e.g. `--apply`.
    func has(_ flag: String) -> Bool { arguments.contains(flag) }

    /// The value after a flag, e.g. `--album NAME`.
    func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// All values of a flag given several times, e.g. `--album A --album B`.
    func values(for flag: String) -> [String] {
        arguments.indices.dropLast().filter { arguments[$0] == flag }.map { arguments[$0 + 1] }
    }

    /// Arguments after the command that are neither a flag nor a flag's value
    /// from `valueFlags` - files to add, a backup identifier. `--volume` always has
    /// a value; without this the iPod's path would end up among the files.
    func positional(valueFlags: Set<String> = []) -> [String] {
        let withValue = valueFlags.union(["--volume"])
        var result: [String] = []
        var skipNext = false
        for argument in arguments.dropFirst() {
            if skipNext { skipNext = false; continue }
            if argument.hasPrefix("--") { skipNext = withValue.contains(argument); continue }
            result.append(argument)
        }
        return result
    }
}

/// An error a command reports to the user - `main` prints it as
/// `error: ...` and exits with code 1. The only place that ends the process.
struct CommandError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
