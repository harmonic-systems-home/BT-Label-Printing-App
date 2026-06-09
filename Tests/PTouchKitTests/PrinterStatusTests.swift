import XCTest
@testable import PTouchKit

final class PrinterStatusTests: XCTestCase {
    // Real 32-byte status captured from a PT-P300BT with 12mm white laminated
    // tape, ready to print: 802042307230...0c01...0108...
    let readyBytes: [UInt8] = [
        0x80, 0x20, 0x42, 0x30, 0x72, 0x30, 0x00, 0x00,
        0x00, 0x00, 0x0c, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x08, 0x00, 0x00, 0x00, 0x00,
    ]

    func testParsesKnownReadyStatus() throws {
        let s = try XCTUnwrap(PrinterStatus(readyBytes))
        XCTAssertEqual(s.model, 0x72)            // PT-P300BT
        XCTAssertEqual(s.mediaWidthMM, 12)       // 12mm tape
        XCTAssertEqual(s.mediaType, 0x01)        // laminated
        XCTAssertFalse(s.hasError)
        XCTAssertTrue(s.isReadyToPrint)
        XCTAssertFalse(s.isPrinting)
        XCTAssertEqual(s.tapeColor, 0x01)        // white tape (observed at [26])
        XCTAssertEqual(s.textColor, 0x08)        // black text (observed at [27])
    }

    func testRejectsShortBuffer() {
        XCTAssertNil(PrinterStatus([0x80, 0x20, 0x42]))
    }

    func testDetectsError() throws {
        var bytes = readyBytes
        bytes[8] = 0x01                          // error information 1 set
        let s = try XCTUnwrap(PrinterStatus(bytes))
        XCTAssertTrue(s.hasError)
        XCTAssertFalse(s.isReadyToPrint)
    }
}
