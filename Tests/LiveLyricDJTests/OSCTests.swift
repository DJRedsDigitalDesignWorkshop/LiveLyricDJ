import Foundation
import XCTest
@testable import LiveLyricDJ

final class OSCTests: XCTestCase {
    func testDecodesArglessPingWithAbsentOrEmptyTypeTags() throws {
        let packets = [
            OSC.encodeString("/Ping"),
            OSC.encode(OSCMessage.message("/Ping")),
        ]

        for packet in packets {
            let messages = try OSC.decodePacket(packet)
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0].address, "/Ping")
            XCTAssertTrue(messages[0].args.isEmpty)
        }
    }

    func testDecodesNestedBundlesInOrder() throws {
        let title = OSC.encode(OSCMessage.message("/Status/Deck/Song/Title", .i(0), .s("Track")))
        let playhead = OSC.encode(OSCMessage.message("/Status/Deck/Playhead", .i(0), .f(12.5), .f(1), .f(120)))
        let packet = makeBundle([title, makeBundle([playhead])])

        let messages = try OSC.decodePacket(packet)

        XCTAssertEqual(messages.map(\.address), [
            "/Status/Deck/Song/Title",
            "/Status/Deck/Playhead",
        ])
    }

    func testRejectsTruncatedBundleHeaders() {
        let completeHeader = makeBundleHeader()
        let truncatedHeaders = [
            Data("#bundle".utf8),
            Data(completeHeader.prefix(8)),
            Data(completeHeader.prefix(15)),
        ]

        for packet in truncatedHeaders {
            XCTAssertThrowsError(try OSC.decodePacket(packet))
        }
    }

    func testRejectsMalformedBundleElementsAndTrailingBytes() {
        var incompleteSize = makeBundleHeader()
        incompleteSize.append(contentsOf: [0, 0, 0])

        var zeroSize = makeBundleHeader()
        appendUInt32BE(0, to: &zeroSize)

        var oversizedElement = makeBundleHeader()
        appendUInt32BE(8, to: &oversizedElement)
        oversizedElement.append(contentsOf: [0, 0, 0, 0])

        var trailingByte = makeBundleHeader()
        trailingByte.append(0)

        for packet in [incompleteSize, zeroSize, oversizedElement, trailingByte] {
            XCTAssertThrowsError(try OSC.decodePacket(packet))
        }
    }

    func testRejectsExcessivelyNestedBundles() {
        var packet = OSC.encode(OSCMessage.message("/Ping"))
        for _ in 0..<32 {
            packet = makeBundle([packet])
        }

        XCTAssertThrowsError(try OSC.decodePacket(packet))
    }

    func testRejectsStringPaddingOutsidePacket() {
        let truncatedAddress = Data([0x2f, 0])

        var truncatedArgument = OSC.encodeString("/String")
        truncatedArgument.append(OSC.encodeString(",s"))
        truncatedArgument.append(contentsOf: [0x41, 0])

        var nonzeroStringPadding = OSC.encodeString("/x")
        nonzeroStringPadding[3] = 0x7f

        for packet in [truncatedAddress, truncatedArgument, nonzeroStringPadding] {
            XCTAssertThrowsError(try OSC.decode(packet))
        }
    }

    func testRejectsBlobPaddingOutsidePacket() {
        var packet = OSC.encodeString("/Blob")
        packet.append(OSC.encodeString(",b"))
        appendUInt32BE(1, to: &packet)
        packet.append(0xaa)

        XCTAssertThrowsError(try OSC.decode(packet))
    }

    func testAcceptsZeroFilledBlobPaddingAndRejectsNonzeroPadding() throws {
        let encoded = OSC.encode(OSCMessage.message("/Blob", .b(Data([0xaa]))))
        let decoded = try OSC.decode(encoded)
        guard case .b(let blob)? = decoded.args.first else {
            return XCTFail("expected blob argument")
        }
        XCTAssertEqual(blob, Data([0xaa]))

        var malformed = encoded
        malformed[malformed.count - 1] = 0x7f
        XCTAssertThrowsError(try OSC.decode(malformed))
    }

    func testRejectsUnexpectedTrailingMessageData() {
        var packet = OSC.encode(OSCMessage.message("/Value", .i(42)))
        packet.append(contentsOf: [0, 0, 0, 0])

        XCTAssertThrowsError(try OSC.decode(packet))
    }

    private func makeBundleHeader() -> Data {
        var data = Data("#bundle\0".utf8)
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        return data
    }

    private func makeBundle(_ packets: [Data]) -> Data {
        var data = makeBundleHeader()
        for packet in packets {
            appendUInt32BE(UInt32(packet.count), to: &data)
            data.append(packet)
        }
        return data
    }

    private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) { data.append(contentsOf: $0) }
    }
}
