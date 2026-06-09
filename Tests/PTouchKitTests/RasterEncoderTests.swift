import XCTest
@testable import PTouchKit

final class RasterEncoderTests: XCTestCase {
    // Reference PackBits decoder, used only to verify the encoder round-trips.
    private func packBitsDecode(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < input.count {
            let n = Int8(bitPattern: input[i]); i += 1
            if n >= 0 {
                let count = Int(n) + 1
                out += input[i..<i+count]; i += count
            } else if n != -128 {
                let count = 1 - Int(n)
                out += Array(repeating: input[i], count: count); i += 1
            }
        }
        return out
    }

    func testKnownEncodings() {
        XCTAssertEqual(PackBits.encode([0xAA, 0xAA, 0xAA]), [0xFE, 0xAA])      // run of 3
        XCTAssertEqual(PackBits.encode([0x01, 0x02, 0x03]), [0x02, 0x01, 0x02, 0x03]) // literals
        XCTAssertEqual(PackBits.encode([]), [])
    }

    func testRoundTrips() {
        let cases: [[UInt8]] = [
            [0x00],
            Array(repeating: 0x00, count: 16),               // typical blank-ish row
            Array(repeating: 0xFF, count: 200),              // long run > 128
            [0x01, 0x01, 0x02, 0x03, 0x03, 0x03, 0x04],
            (0..<256).map { UInt8($0 & 0xFF) },              // all-distinct sweep
            [0xAA, 0xAA, 0x01, 0x02, 0xFF, 0xFF, 0xFF],
        ]
        for input in cases {
            XCTAssertEqual(packBitsDecode(PackBits.encode(input)), input, "round-trip failed")
        }
    }

    func testRasterLineFraming() {
        // Non-blank row -> 'G' + little-endian length + payload.
        let row: [UInt8] = [0x00, 0xFF, 0x00, 0x00]
        let out = RasterEncoder.encode(rows: [row], compress: false)
        XCTAssertEqual(out[0], 0x47)                          // 'G'
        XCTAssertEqual(out[1], UInt8(row.count))             // len low
        XCTAssertEqual(out[2], 0x00)                          // len high
        XCTAssertEqual(Array(out[3...]), row)
    }

    func testBlankRowEmitsZ() {
        let blank = Array(repeating: UInt8(0), count: 16)
        XCTAssertEqual(RasterEncoder.encode(rows: [blank], compress: true), [0x5A]) // 'Z'
    }
}
