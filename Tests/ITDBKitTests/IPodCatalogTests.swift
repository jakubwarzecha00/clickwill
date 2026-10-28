import Foundation
import Testing
@testable import ITDBKit

/// The generation from what the iPod says about itself; the color only from confirmed units.
@Suite("iPod generation and color")
struct IPodCatalogTests {

    @Test("the test classic: USB 0x1261, firmware 2.0.4, 160 GB -> 2009, black (confirmed suffix)")
    func testClassic() throws {
        let entry = try #require(IPodCatalog.entry(serial: "8K1000009ZU", usbProductID: 0x1261,
                                                   firmwareVersion: "2.0.4", capacity: 159_840_000_000))
        #expect(entry.generation == .classic3)
        #expect(entry.finish == .black)
        #expect(entry.name == "iPod classic (2009), Black")
    }

    @Test("the test nano: USB 0x1260 -> nano 2G, silver")
    func testNano() throws {
        let entry = try #require(IPodCatalog.entry(serial: "5U1000AAVQ5", usbProductID: 0x1260,
                                                   firmwareVersion: "1.1.3", capacity: 1_960_000_000))
        #expect(entry.generation == .nano2)
        #expect(entry.finish == .silver)
    }

    @Test("an unknown suffix: the generation yes, the color no")
    func unknownSerialNoFinish() throws {
        let entry = try #require(IPodCatalog.entry(serial: "XXXXXXXXQQQ", usbProductID: 0x1263,
                                                   firmwareVersion: nil, capacity: 8_000_000_000))
        #expect(entry.generation == .nano4)
        #expect(entry.finish == nil)
        #expect(entry.name == "iPod nano (4th generation)")
    }

    @Test("a confirmed suffix on an iPod of another family - no color")
    func suffixOnOtherFamily() throws {
        let entry = try #require(IPodCatalog.entry(serial: "8K1000009ZU", usbProductID: 0x1260,
                                                   firmwareVersion: nil, capacity: 2_000_000_000))
        #expect(entry.generation == .nano2)
        #expect(entry.finish == nil)
    }

    @Test("classic: 2007 by firmware 1.x, 2008 and 2009 by disk with firmware 2.x")
    func classicYears() {
        #expect(IPodCatalog.generation(usbProductID: 0x1261, firmwareVersion: "1.1.2", capacity: 159_000_000_000) == .classic1)
        #expect(IPodCatalog.generation(usbProductID: 0x1261, firmwareVersion: "2.0.1", capacity: 119_000_000_000) == .classic2)
        #expect(IPodCatalog.generation(usbProductID: 0x1261, firmwareVersion: "2.0.4", capacity: 159_000_000_000) == .classic3)
    }

    @Test("classic without firmware: 80 and 120 GB unambiguous, 160 GB not")
    func classicWithoutFirmware() {
        #expect(IPodCatalog.generation(usbProductID: 0x1261, firmwareVersion: nil, capacity: 79_000_000_000) == .classic1)
        #expect(IPodCatalog.generation(usbProductID: 0x1261, firmwareVersion: nil, capacity: 119_000_000_000) == .classic2)
        #expect(IPodCatalog.generation(usbProductID: 0x1261, firmwareVersion: nil, capacity: 159_000_000_000) == nil)
    }

    @Test("without USB or with an unknown identifier - no entry")
    func noUSB() {
        #expect(IPodCatalog.entry(serial: "8K1000009ZU", usbProductID: nil, firmwareVersion: "2.0.4", capacity: 0) == nil)
        #expect(IPodCatalog.entry(serial: nil, usbProductID: 0x1299, firmwareVersion: nil, capacity: 0) == nil)
    }

    @Test("iPod 1G/2G and 3G: always white, also without a confirmed suffix; 4G - color unknown")
    func whiteOnlyGenerations() throws {
        let early = try #require(IPodCatalog.entry(serial: nil, usbProductID: 0x1202, firmwareVersion: nil, capacity: 0))
        #expect(early.generation == .firstSecond)
        #expect(early.finishOrDefault == .white)
        #expect(IPodCatalog.entry(serial: nil, usbProductID: 0x1201, firmwareVersion: nil, capacity: 0)?.finishOrDefault == .white)
        #expect(IPodCatalog.entry(serial: nil, usbProductID: 0x1203, firmwareVersion: nil, capacity: 0)?.finishOrDefault == nil)
    }

    @Test("every confirmed suffix points to a family known from USB")
    func confirmedSuffixesConsistent() {
        for (_, confirmed) in IPodCatalog.confirmedFinishes {
            #expect(USBIdentity.families[confirmed.usbProductID] != nil)
        }
    }
}
