#if os(macOS)
import Foundation
import CoreGraphics
import CoreText

/// A rendered label: the printer raster rows plus a readable preview image.
public struct RenderedLabel {
    /// Raster lines in tape-feed order (each `bufferWidth/8` bytes, MSB-first, bit 1 = black).
    public let rows: [[UInt8]]
    /// Readable label image (black on white, length × printableHeight) for on-screen preview.
    public let preview: CGImage
    public var lengthDots: Int { rows.count }
}

/// Renders text to printer raster rows for a PT‑P300BT‑class device.
///
/// The print head is `bufferWidth` dots across (128); only the centre
/// `printableHeight` dots (64 ≈ 9 mm on 12 mm tape) actually print. A label of
/// length L dots is L raster lines; the text's columns become raster lines and
/// its rows map onto the centred dot band (the known-good transpose pipeline).
public struct LabelRenderer {
    public var printableHeight: Int
    public var bufferWidth: Int
    public var flipLength: Bool       // reverse line order (mirror along length)
    public var flipWidth: Bool        // reverse dots (flip across width)

    public init(printableHeight: Int = 64, bufferWidth: Int = 128,
                flipLength: Bool = false, flipWidth: Bool = false) {
        self.printableHeight = printableHeight
        self.bufferWidth = bufferWidth
        self.flipLength = flipLength
        self.flipWidth = flipWidth
    }

    /// Render one or more lines of text (`\n` separates lines; literal "\\n" is
    /// also accepted). Returns nil only if a drawing context can't be created.
    public func render(text: String, fontName: String = "Helvetica",
                       sideMarginDots: Int = 12, lineSpacing: CGFloat = 1.12) -> RenderedLabel? {
        let H = printableHeight
        let normalized = text.replacingOccurrences(of: "\\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let n = max(1, lines.count)

        // Size the font so all lines fit ~92% of the printable height.
        let probe = CTFontCreateWithName(fontName as CFString, 100, nil)
        let probeLH = Double(CTFontGetAscent(probe) + CTFontGetDescent(probe))
        let effectiveLines = Double(n) + Double(n - 1) * Double(lineSpacing - 1)
        let size = probeLH > 0 ? 100.0 * (Double(H) * 0.92) / (probeLH * effectiveLines) : Double(H)
        let font = CTFontCreateWithName(fontName as CFString, CGFloat(size), nil)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let lineH = ascent + descent
        let gap = lineH * (lineSpacing - 1)
        let blockHeight = lineH * CGFloat(n) + gap * CGFloat(n - 1)

        func makeLine(_ s: String) -> (CTLine, Double) {
            let attrs: [NSAttributedString.Key: Any] = [
                .init(rawValue: kCTFontAttributeName as String): font,
                .init(rawValue: kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: s, attributes: attrs) as CFAttributedString)
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            return (line, w)
        }
        let ctLines = lines.map(makeLine)
        let maxWidth = ctLines.map(\.1).max() ?? 0
        let W = max(1, Int(maxWidth.rounded(.up)) + 2 * sideMarginDots)

        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Draw lines top-to-bottom, vertically centred as a block (CG y is up).
        let topY = (CGFloat(H) + blockHeight) / 2
        for (k, (line, lineWidth)) in ctLines.enumerated() {
            let baseline = topY - CGFloat(k) * (lineH + gap) - ascent
            ctx.textPosition = CGPoint(x: (CGFloat(W) - CGFloat(lineWidth)) / 2, y: baseline)
            CTLineDraw(line, ctx)
        }

        guard let preview = ctx.makeImage(), let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * H)
        let bpr = ctx.bytesPerRow
        let bytesPerRow = bufferWidth / 8
        let offset = (bufferWidth - H) / 2

        var rows: [[UInt8]] = []
        rows.reserveCapacity(W)
        for col in 0..<W {
            var lineBytes = [UInt8](repeating: 0, count: bytesPerRow)
            for r in 0..<H where ptr[r * bpr + col] < 128 {        // dark pixel -> print
                let dot = offset + (flipWidth ? (H - 1 - r) : r)
                lineBytes[dot / 8] |= (0x80 >> (dot % 8))
            }
            rows.append(lineBytes)
        }
        return RenderedLabel(rows: flipLength ? rows.reversed() : rows, preview: preview)
    }
}
#endif
