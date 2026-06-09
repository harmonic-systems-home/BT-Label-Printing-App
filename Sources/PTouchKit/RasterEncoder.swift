import Foundation

/// TIFF/PackBits run-length compression, as used by the Brother raster
/// "compression mode 2". Independent implementation of the public PackBits
/// algorithm.
public enum PackBits {
    /// Encode one row of bytes with PackBits.
    /// - Literal run: `count-1` (0…127) followed by `count` literal bytes.
    /// - Repeat run: `257-count` (129…255 == -1…-127 signed) then the byte.
    /// - 0x80 is unused (no-op).
    public static func encode(_ input: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        let n = input.count
        while i < n {
            // Count a run of identical bytes (max 128).
            var runLen = 1
            while i + runLen < n, input[i + runLen] == input[i], runLen < 128 {
                runLen += 1
            }
            if runLen >= 2 {
                out.append(UInt8(257 - runLen))      // negative count
                out.append(input[i])
                i += runLen
            } else {
                // Gather a literal run up to 128 bytes, stopping when a >=2 repeat
                // begins (so the next iteration can encode it efficiently).
                let start = i
                i += 1
                while i < n, (i - start) < 128 {
                    if i + 1 < n, input[i] == input[i + 1] { break }
                    i += 1
                }
                let count = i - start
                out.append(UInt8(count - 1))         // literal count - 1
                out.append(contentsOf: input[start..<i])
            }
        }
        return out
    }
}

/// Turns a 1-bit raster image (rows of `bytesPerRow` bytes, MSB = leftmost dot)
/// into the printer byte stream of per-line transfer commands.
public enum RasterEncoder {
    /// - Parameters:
    ///   - rows: each element is one raster line, `bytesPerRow` bytes, MSB first.
    ///   - compress: use PackBits (compression mode 2) when true.
    public static func encode(rows: [[UInt8]], compress: Bool) -> [UInt8] {
        var out: [UInt8] = []
        for row in rows {
            if row.allSatisfy({ $0 == 0 }) {
                out += PTouchCommand.blankLine
            } else {
                let payload = compress ? PackBits.encode(row) : row
                out += PTouchCommand.rasterLine(payload)
            }
        }
        return out
    }
}
