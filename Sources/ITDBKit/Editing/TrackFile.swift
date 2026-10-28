import Foundation

/// Replacing the audio file of an existing track: the `mhit` record starts pointing to
/// the new file and carries its parameters. The track itself stays the same - identifier,
/// positions in the tables, plays and artwork are untouched.
///
/// The file kind goes through `settingFileKind`, not through the text description alone.
/// The first version set only `mhod` 6 and left the container code at
/// 0x18 from before the conversion - on the device this left one track described
/// as Apple Lossless with the code `WAV `.
extension ITTrack {

    /// The new file parameters. `relativePath` is relative to the volume root,
    /// with slashes; the conversion to the colon form happens here.
    public func replacingFile(
        relativePath: String, sizeBytes: UInt32, durationMilliseconds: UInt32? = nil,
        bitRate: UInt32, sampleRate: UInt32, kind: TrackFileKind
    ) -> ITTrack {
        var copy = self
        copy.sizeBytes = sizeBytes
        copy.sizeBytesSecondary = sizeBytes
        copy.bitRate = bitRate
        copy.rawSampleRate = sampleRate << 16
        copy.sampleRateFloat = Float(sampleRate)
        if let durationMilliseconds { copy.durationMilliseconds = durationMilliseconds }
        let ipodPath = ":" + relativePath.split(separator: "/").joined(separator: ":")
        return copy.setting(.location, to: ipodPath).settingFileKind(kind)
    }
}
