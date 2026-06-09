#if os(macOS)
import Foundation
import CoreGraphics
import CoreText
import ImageIO

/// How text is sized to the printable height.
public enum SizingMode: String, Sendable, CaseIterable, Codable {
    /// Largest size that fits this specific text's ink (fills the tape; default).
    case fitText
    /// Consistent cap-height sizing regardless of the specific glyphs.
    case capHeight
}

/// A rendered label: printer raster rows plus a readable preview image.
public struct RenderedLabel {
    public let rows: [[UInt8]]
    public let preview: CGImage
    public var lengthDots: Int { rows.count }
}

/// Renders text (and an optional leading image/PDF) to printer raster rows for a
/// PT‑P300BT‑class device. Print head = `bufferWidth` dots (128); only the centre
/// `printableHeight` dots (64 ≈ 9 mm) print.
public struct LabelRenderer {
    public var printableHeight: Int
    public var bufferWidth: Int
    public var flipLength: Bool
    public var flipWidth: Bool

    public init(printableHeight: Int = 64, bufferWidth: Int = 128,
                flipLength: Bool = false, flipWidth: Bool = false) {
        self.printableHeight = printableHeight
        self.bufferWidth = bufferWidth
        self.flipLength = flipLength
        self.flipWidth = flipWidth
    }

    /// Grayscale bitmap, row-major, row 0 = top, 0 = black … 255 = white.
    private struct Gray { var width: Int; var height: Int; var px: [UInt8] }

    public func render(text: String,
                       fontName: String = "Helvetica",
                       sizing: SizingMode = .fitText,
                       imageURL: URL? = nil,
                       mergeGapDots: Int = 24,
                       sideMarginDots: Int = 12,
                       lineSpacing: CGFloat = 1.12,
                       fillFraction: CGFloat = 0.95) -> RenderedLabel? {
        let H = printableHeight
        var parts: [Gray] = []
        if let url = imageURL, let img = loadImageGray(url, height: H) { parts.append(img) }
        let normalized = text.replacingOccurrences(of: "\\n", with: "\n")
        if !normalized.isEmpty,
           let t = textGray(normalized, fontName: fontName, sizing: sizing,
                            lineSpacing: lineSpacing, fillFraction: fillFraction,
                            sideMarginDots: sideMarginDots) {
            parts.append(t)
        }
        guard !parts.isEmpty else { return nil }
        return rasterize(compose(parts, gap: mergeGapDots, height: H))
    }

    // MARK: - Text

    private func textGray(_ text: String, fontName: String, sizing: SizingMode,
                          lineSpacing: CGFloat, fillFraction: CGFloat,
                          sideMarginDots: Int) -> Gray? {
        let H = printableHeight
        let lines = text.components(separatedBy: "\n")

        func line(_ s: String, _ font: CTFont) -> CTLine {
            let attrs: [NSAttributedString.Key: Any] = [
                .init(rawValue: kCTFontAttributeName as String): font,
                .init(rawValue: kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ]
            return CTLineCreateWithAttributedString(
                NSAttributedString(string: s, attributes: attrs) as CFAttributedString)
        }

        let S0: CGFloat = 100
        let probe = CTFontCreateWithName(fontName as CFString, S0, nil)
        let asc = CTFontGetAscent(probe), desc = CTFontGetDescent(probe)
        let cap = CTFontGetCapHeight(probe)
        let step0 = (asc + desc) * lineSpacing
        var top0 = -CGFloat.greatestFiniteMagnitude, bot0 = CGFloat.greatestFiniteMagnitude
        for (k, s) in lines.enumerated() {
            let baseline = -CGFloat(k) * step0
            switch sizing {
            case .capHeight:
                top0 = max(top0, baseline + cap); bot0 = min(bot0, baseline - desc)
            case .fitText:
                let b = CTLineGetBoundsWithOptions(line(s, probe), .useGlyphPathBounds)
                guard !b.isNull, b.height > 0 else { continue }
                top0 = max(top0, baseline + b.maxY); bot0 = min(bot0, baseline + b.minY)
            }
        }
        if top0 < bot0 { top0 = cap; bot0 = -desc }
        let scale = (CGFloat(H) * fillFraction) / max(1, top0 - bot0)
        let step = step0 * scale
        let font = CTFontCreateWithName(fontName as CFString, S0 * scale, nil)
        let real: [(CTLine, CGFloat)] = lines.map {
            let l = line($0, font); return (l, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)))
        }
        let W = max(1, Int((real.map(\.1).max() ?? 0).rounded(.up)) + 2 * sideMarginDots)
        guard let ctx = grayContext(W, H) else { return nil }
        let baseline0 = CGFloat(H) / 2 - (top0 + bot0) / 2 * scale
        for (k, (l, w)) in real.enumerated() {
            ctx.textPosition = CGPoint(x: (CGFloat(W) - w) / 2, y: baseline0 - CGFloat(k) * step)
            CTLineDraw(l, ctx)
        }
        return readGray(ctx, W, H)
    }

    // MARK: - Image / PDF

    private func loadImageGray(_ url: URL, height H: Int) -> Gray? {
        if url.pathExtension.lowercased() == "pdf" { return loadPDFGray(url, height: H) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let sW = max(1, Int((CGFloat(cg.width) * CGFloat(H) / CGFloat(cg.height)).rounded()))
        guard let ctx = grayContext(sW, H) else { return nil }
        ctx.interpolationQuality = .high
        // Flip so the top-down CGImage draws upright in the bottom-up context.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: sW, height: H))
        ctx.restoreGState()
        return cropHorizontally(readGray(ctx, sW, H))
    }

    private func loadPDFGray(_ url: URL, height H: Int) -> Gray? {
        guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.height > 0 else { return nil }
        let scale = CGFloat(H) / box.height
        let sW = max(1, Int((box.width * scale).rounded()))
        guard let ctx = grayContext(sW, H) else { return nil }
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)               // PDF is y-up: draws upright already
        ctx.restoreGState()
        return cropHorizontally(readGray(ctx, sW, H))
    }

    /// Trim left/right whitespace columns so the merge gap is consistent.
    private func cropHorizontally(_ g: Gray, threshold: UInt8 = 200) -> Gray {
        var lo = g.width, hi = -1
        for c in 0..<g.width {
            var dark = false
            for r in 0..<g.height where g.px[r * g.width + c] < threshold { dark = true; break }
            if dark { lo = min(lo, c); hi = max(hi, c) }
        }
        guard hi >= lo else { return g }
        let w = hi - lo + 1
        var px = [UInt8](repeating: 255, count: w * g.height)
        for r in 0..<g.height { for c in 0..<w { px[r * w + c] = g.px[r * g.width + (lo + c)] } }
        return Gray(width: w, height: g.height, px: px)
    }

    // MARK: - Compose + rasterize

    private func compose(_ parts: [Gray], gap: Int, height H: Int) -> Gray {
        let total = parts.map(\.width).reduce(0, +) + gap * max(0, parts.count - 1)
        var px = [UInt8](repeating: 255, count: total * H)
        var x = 0
        for (i, p) in parts.enumerated() {
            for r in 0..<H { for c in 0..<p.width { px[r * total + (x + c)] = p.px[r * p.width + c] } }
            x += p.width + (i < parts.count - 1 ? gap : 0)
        }
        return Gray(width: max(1, total), height: H, px: px)
    }

    private func rasterize(_ g: Gray) -> RenderedLabel? {
        let H = g.height
        guard let ctx = grayContext(g.width, H), let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * H)
        for r in 0..<H { for c in 0..<g.width { ptr[r * ctx.bytesPerRow + c] = g.px[r * g.width + c] } }
        guard let preview = ctx.makeImage() else { return nil }

        let bytesPerRow = bufferWidth / 8
        let offset = (bufferWidth - H) / 2
        var rows: [[UInt8]] = []
        rows.reserveCapacity(g.width)
        for col in 0..<g.width {
            var lineBytes = [UInt8](repeating: 0, count: bytesPerRow)
            for r in 0..<H where g.px[r * g.width + col] < 128 {
                let dot = offset + (flipWidth ? (H - 1 - r) : r)
                lineBytes[dot / 8] |= (0x80 >> (dot % 8))
            }
            rows.append(lineBytes)
        }
        return RenderedLabel(rows: flipLength ? rows.reversed() : rows, preview: preview)
    }

    // MARK: - Helpers

    private func grayContext(_ w: Int, _ h: Int) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx
    }

    private func readGray(_ ctx: CGContext, _ w: Int, _ h: Int) -> Gray {
        let bpr = ctx.bytesPerRow
        let ptr = ctx.data!.bindMemory(to: UInt8.self, capacity: bpr * h)
        var px = [UInt8](repeating: 255, count: w * h)
        for r in 0..<h { for c in 0..<w { px[r * w + c] = ptr[r * bpr + c] } }
        return Gray(width: w, height: h, px: px)
    }
}
#endif
