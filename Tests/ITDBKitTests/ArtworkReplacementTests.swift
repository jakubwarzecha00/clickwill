import Foundation
import CoreGraphics
import Testing
@testable import ITDBKit

/// A 40x20 image: the top half red, the bottom half blue, the left edge green.
private func sample() -> CGImage {
    let w = 40, h = 20
    var px = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        if x < 4 { px[i] = 0; px[i+1] = 255; px[i+2] = 0 }
        else if y < h / 2 { px[i] = 255; px[i+1] = 0; px[i+2] = 0 }
        else { px[i] = 0; px[i+1] = 0; px[i+2] = 255 }
    } }
    return ITHMBImage(width: w, height: h, rgba: px).makeCGImage()!
}

@Suite("Artwork replacement")
struct ArtworkReplacementTests {

    @Test("rasterizing: orientation kept, aspect fill with center cropping")
    func rendering() throws {
        // A 20x20 square from a 40x20 image: scale 1, cropping 10 px on both sides -
        // the green edge drops off, the top red, the bottom blue.
        let out = try ITHMBImage(rendering: sample(), width: 20, height: 20)
        func px(_ x: Int, _ y: Int) -> [UInt8] { Array(out.rgba[(y * 20 + x) * 4 ..< (y * 20 + x) * 4 + 3]) }
        #expect(px(10, 2) == [255, 0, 0])
        #expect(px(10, 17) == [0, 0, 255])
        #expect(px(0, 2) == [255, 0, 0])   // the green edge cropped
    }

    @Test("writing in place: the bytes go to the offset, an error rolls back the slices already written")
    func writeAndRollback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-\(UUID().uuidString)", isDirectory: true)
        let artwork = root.appendingPathComponent("iPod_Control/Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = IPodPaths(mountPoint: root)
        // A file with two 4x2 RGB565 slots (16 B), filled with 0xAA.
        let original = Data(repeating: 0xAA, count: 64)
        try original.write(to: artwork.appendingPathComponent("F9_1.ithmb"))
        let a = ArtworkVariant(correlationID: 9, fileName: ":F9_1.ithmb", byteOffset: 0, byteCount: 16, width: 4, height: 2)
        let b = ArtworkVariant(correlationID: 9, fileName: ":F9_1.ithmb", byteOffset: 32, byteCount: 16, width: 4, height: 2)
        let slots = [ArtworkReplacement.Slot(variant: a), ArtworkReplacement.Slot(variant: b)]

        let white = ITHMBImage(width: 4, height: 2, rgba: [UInt8](repeating: 255, count: 32))
        let count = try ArtworkReplacement.write(slots, in: paths) { _, _ in white }
        #expect(count == 2)
        var data = try Data(contentsOf: artwork.appendingPathComponent("F9_1.ithmb"))
        #expect(data[0..<16] == Data(repeating: 0xFF, count: 16))
        #expect(data[16..<32] == Data(repeating: 0xAA, count: 16))   // between the slots untouched
        #expect(data[32..<48] == Data(repeating: 0xFF, count: 16))

        // The second slice fails (wrong size) - the first goes back to the 0xFF from before the attempt.
        try original.write(to: artwork.appendingPathComponent("F9_1.ithmb"))
        var calls = 0
        #expect(throws: (any Error).self) {
            try ArtworkReplacement.write(slots, in: paths) { w, h in
                calls += 1
                return calls == 1 ? white : ITHMBImage(width: 1, height: 1, rgba: [0, 0, 0, 255])
            }
        }
        data = try Data(contentsOf: artwork.appendingPathComponent("F9_1.ithmb"))
        #expect(data == original)
    }
}
