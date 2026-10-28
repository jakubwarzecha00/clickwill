import Foundation

/// Which iPod this is - as far as the device says about itself.
///
/// **The model name is cosmetic.** Not a single decision about writing
/// follows from it; those are made by `DatabaseFormat` from the database header.
/// The separation is deliberate: the model table may be incomplete or out of date,
/// and a mistake in it must end with a wrong label on screen, not a broken database.
public struct IPodModel: Sendable, Hashable {

    /// Where we got the name from - and how far we trust it.
    public enum Source: String, Sendable {
        /// `SysInfoExtended`, the file in which the device itself gives its model.
        case sysInfoExtended
        /// The older `SysInfo` in text form.
        case sysInfo
        /// Family from the USB product identifier - without capacity or revision,
        /// but given by the firmware. That is the case on a Classic that
        /// has an empty `SysInfo` and no `SysInfoExtended`.
        case usb
        /// Nothing gave the model - we only have what follows from the database format.
        case databaseOnly
    }

    /// The model number as the device gives it, e.g. `A1199`.
    public let modelNumber: String?
    /// The name to show.
    public let name: String
    public let source: Source

    /// Whether the name comes from a recognized model number or is a default.
    /// The interface must show this instead of pretending to be certain.
    public var isConfirmed: Bool { source == .usb || (modelNumber != nil && source != .databaseOnly) }

    /// Numbers we can name. The list is **incomplete and will stay that way** -
    /// we add only models we have had in hand or whose number
    /// we have confirmed. An unrecognized number is shown as given,
    /// instead of guessing the generation.
    static let known: [String: String] = [
        "A1238": "iPod classic",
        "A1199": "iPod nano (2nd generation)",
    ]

    /// Reads the model from the device files, and when there are none - describes it by
    /// what its database is.
    public static func detect(paths: IPodPaths, format: DatabaseFormat, usb: USBIdentity? = nil) -> IPodModel {
        if let number = fromSysInfoExtended(at: paths.sysInfoExtended) {
            return IPodModel(modelNumber: number, name: name(for: number), source: .sysInfoExtended)
        }
        if let number = fromSysInfo(at: paths.sysInfo) {
            return IPodModel(modelNumber: number, name: name(for: number), source: .sysInfo)
        }
        if let family = usb?.familyName {
            return IPodModel(modelNumber: nil, name: family, source: .usb)
        }
        return IPodModel(modelNumber: nil, name: fallbackName(for: format), source: .databaseOnly)
    }

    static func name(for number: String) -> String {
        known[number.uppercased()] ?? "iPod \(number)"
    }

    /// When the device does not give its model, we say only what we know for sure:
    /// which side of the 2007 line its database stands on.
    static func fallbackName(for format: DatabaseFormat) -> String {
        switch format.signing {
        case .hash58: return "iPod (2007 or later)"
        case .presumedUnsigned: return "iPod (pre-2007)"
        case .unknown: return "iPod (unrecognised database)"
        }
    }

    // MARK: - Sources

    static func fromSysInfoExtended(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any]
        else { return nil }
        for key in ["ModelNumStr", "ModelNum", "modelNumber"] {
            if let value = dictionary[key] as? String { return clean(value) }
        }
        return nil
    }

    static func fromSysInfo(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0].caseInsensitiveCompare("ModelNumStr") == .orderedSame
            else { continue }
            return clean(parts[1])
        }
        return nil
    }

    /// iPods give the number with a leading `x` or `M`, e.g. `xA1199`. We strip it,
    /// so the number can be compared with what is printed on the case.
    static func clean(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        while let first = value.first, first == "X" || first == "M" || first == "P" {
            guard value.dropFirst().first?.isNumber == false else { break }
            value.removeFirst()
        }
        return value.isEmpty ? nil : value
    }
}

