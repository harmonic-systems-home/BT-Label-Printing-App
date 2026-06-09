#if os(macOS)
import Foundation
import CoreGraphics
import CoreText

/// Renders text to printer raster rows for a PT‑P300BT‑class device.
///
/// The print head is `bufferWidth` dots across (128); only the centre
/// `printableHeight` dots (64 ≈ 9 mm on 12 mm tape) actually print. A label of
/// length L dots is L raster lines, each `bufferWidth/8` bytes, MSB = first dot,
/// bit 1 = black. The text's columns become raster lines and its rows map onto
/// the centred dot band — equivalent to the known‑good transpose pipeline.
public struct LabelRenderer {
    public var printableHeight: Int
    public var bufferWidth: Int
    /// Reverse raster-line order (text mirrored along the tape length).
    public var flipLength: Bool
    /// Reverse dot order within a line (text flipped across the tape width).
    public var flipWidth: Bool

    public init(printableHeight: Int = 64, bufferWidth: Int = 128,
                flipLength: Bool = false, flipWidth: Bool = false) {
        self.printableHeight = printableHeight
        self.bufferWidth = bufferWidth
        self.flipLength = flipLength
        self.flipWidth = flipWidth
    }

    /// Render a single line of text. Returns raster rows in tape-feed order.
    public func render(text: String, fontName: String = "Helvetica",
                       sideMarginDots: Int = 10) -> [[UInt8]] {
        let H = printableHeight

        // Pick a font size whose line height fills ~90% of the printable band.
        let probe = CTFontCreateWithName(fontName as CFString, 100, nil)
        let probeHeight = CTFontGetAscent(probe) + CTFontGetDescent(probe)
        let size = probeHeight > 0 ? 100.0 * (Double(H) * 0.9) / Double(probeHeight) : Double(H)
        let font = CTFontCreateWithName(fontName as CFString, CGFloat(size), nil)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)

        let attrs: [NSAttributedString.Key: Any] = [
            .init(rawValue: kCTFontAttributeName as String): font,
            .init(rawValue: kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let ctLine = CTLineCreateWithAttributedString(attr as CFAttributedString)
        var ascD: CGFloat = 0, descD: CGFloat = 0, leadD: CGFloat = 0
        let textWidth = CTLineGetTypographicBounds(ctLine, &ascD, &descD, &leadD)
        let W = max(1, Int(textWidth.rounded(.up)) + 2 * sideMarginDots)

        // Draw black text on white into a grayscale bitmap (row 0 = top).
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let baseline = (CGFloat(H) - ascent - descent) / 2 + descent   // vertical centre
        ctx.textPosition = CGPoint(x: CGFloat(sideMarginDots), y: baseline)
        CTLineDraw(ctLine, ctx)

        guard let data = ctx.data else { return [] }
        let ptr = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * H)
        let bpr = ctx.bytesPerRow
        let bytesPerRow = bufferWidth / 8
        let offset = (bufferWidth - H) / 2

        func isBlack(col: Int, row: Int) -> Bool { ptr[row * bpr + col] < 128 }

        var rows: [[UInt8]] = []
        rows.reserveCapacity(W)
        for col in 0..<W {                       // each text column -> one raster line
            var line = [UInt8](repeating: 0, count: bytesPerRow)
            for r in 0..<H where isBlack(col: col, row: r) {
                let dot = offset + (flipWidth ? (H - 1 - r) : r)
                line[dot / 8] |= (0x80 >> (dot % 8))
            }
            rows.append(line)
        }
        return flipLength ? rows.reversed() : rows
    }
}
#endif
