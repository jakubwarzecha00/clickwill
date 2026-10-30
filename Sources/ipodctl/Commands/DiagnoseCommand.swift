import Foundation
import ITDBKit
import ClickwillModel

/// `diagnose [--rockbox]` - every diagnostic check (`Diagnostics`), read-only. The same
/// result the app shows; required checks decide whether an unconfirmed model may be
/// allowed experimental writing.
enum DiagnoseCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let result = Diagnostics.run(on: device, isMusicRunning: call.environment.isMusicRunning)
        print("\(device.model.name) at \(device.volume.mountPoint.path) - policy \(device.writePolicy)")
        for group in Diagnostics.Group.allCases {
            let checks = result.checks.filter { $0.group == group }
            guard !checks.isEmpty else { continue }
            print("\n\(group.rawValue)")
            for check in checks {
                let weight = check.weight == .required ? "required" : "advisory"
                print("  \(mark(check.status)) \(check.id.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)) \(check.detail)  [\(weight)]")
            }
        }
        print("")
        print(result.verdict)
        if !result.measurements.isEmpty {
            print("\nmeasurements")
            for line in result.measurements { print("  \(line)") }
        }

        guard let rockbox = RockboxInstallation.detect(at: device.volume.mountPoint) else {
            if call.has("--rockbox") { print("\nRockbox: not installed") }
            return
        }
        print("\nRockbox \(rockbox.version ?? "?") (\(rockbox.target ?? "?"))")
        guard call.has("--rockbox") else { print("  --rockbox reads every song file and lists albums that look different there"); return }
        let report = await RockboxReport.build(library: try device.readLibrary(), paths: device.paths, installation: rockbox)
        for line in report.reportLines { print("  \(line)") }
    }

    private static func mark(_ status: Diagnostics.Status) -> String {
        switch status {
        case .passed: "OK  "
        case .warning: "WARN"
        case .failed: "FAIL"
        case .info: "INFO"
        }
    }
}
