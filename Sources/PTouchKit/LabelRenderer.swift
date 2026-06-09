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
                       sideMarginDots: Int = 12, lineSpacing: CGFloat = 1.12,
                       fillFraction: CGFloat = 0.95) -> RenderedLabel? {
        let H = printableHeight
        let normalized = text.replacingOccurrences(of: "\\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        func makeLine(_ s: String, _ font: CTFont) -> CTLine {
            let attrs: [NSAttributedString.Key: Any] = [
                .init(rawValue: kCTFontAttributeName as String): font,
                .init(rawValue: kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ]
            return CTLineCreateWithAttributedString(
                NSAttributedString(string: s, attributes: attrs) as CFAttributedString)
        }

        // Size by the actual glyph *ink* bounds (not the font's nominal line
        // box) so the text fills the printable height consistently across fonts,
        // which vary a lot in internal leading. Probe at a reference size, then
        // scale linearly.
        let S0: CGFloat = 100
        let probeFont = CTFontCreateWithName(fontName as CFString, S0, nil)
        let step0 = (CTFontGetAscent(probeFont) + CTFontGetDescent(probeFont)) * lineSpacing
        var inkTop0 = -CGFloat.greatestFiniteMagnitude
        var inkBot0 = CGFloat.greatestFiniteMagnitude
        for (k, s) in lines.enumerated() {
            let b = CTLineGetBoundsWithOptions(makeLine(s, probeFont), .useGlyphPathBounds)
            guard !b.isNull, b.height > 0 else { continue }
            let baseline = -CGFloat(k) * step0
            inkTop0 = max(inkTop0, baseline + b.maxY)
            inkBot0 = min(inkBot0, baseline + b.minY)
        }
        if inkTop0 < inkBot0 {                       // all-empty fallback
            inkTop0 = CTFontGetAscent(probeFont); inkBot0 = -CTFontGetDescent(probeFont)
        }
        let scale = (CGFloat(H) * fillFraction) / max(1, inkTop0 - inkBot0)
        let size = S0 * scale
        let step = step0 * scale

        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let realLines: [(CTLine, CGFloat)] = lines.map { s in
            let l = makeLine(s, font)
            return (l, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)))
        }
        let maxWidth = realLines.map(\.1).max() ?? 0
        let W = max(1, Int(maxWidth.rounded(.up)) + 2 * sideMarginDots)

        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Centre the ink block vertically (CG y is up).
        let baseline0 = CGFloat(H) / 2 - (inkTop0 + inkBot0) / 2 * scale
        for (k, (line, lineWidth)) in realLines.enumerated() {
            ctx.textPosition = CGPoint(x: (CGFloat(W) - lineWidth) / 2,
                                       y: baseline0 - CGFloat(k) * step)
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
