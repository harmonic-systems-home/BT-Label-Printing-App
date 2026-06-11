#if os(macOS)
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// A rendered label: printer raster rows plus a readable preview image.
public struct RenderedLabel {
    public let rows: [[UInt8]]
    public let preview: CGImage
    /// Width in dots of each rendered cell, in order (for a cell ruler).
    public let cellWidths: [Int]
    /// Gap (dots) between cells and end margin (dots) used in this layout.
    public let gapDots: Int
    public let marginDots: Int
    public var lengthDots: Int { rows.count }
}

/// Renders a label (a list of cells: text / image / symbol, each normal or
/// inverted) to printer raster rows for a PT‑P300BT‑class device. Print head =
/// `bufferWidth` dots (128); only the centre `printableHeight` dots (64 ≈ 9 mm)
/// print. A label of length L dots is L raster lines.
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

    // MARK: - Public API

    /// Render a label from its cells.
    public func render(cells: [LabelCell], gapDots: Int = 18, endMarginDots: Int = 18,
                       lineSpacing: CGFloat = 1.05, fillFraction: CGFloat = 1.0) -> RenderedLabel? {
        let grays = cells.compactMap {
            renderCell($0, lineSpacing: lineSpacing, fillFraction: fillFraction)
        }
        guard !grays.isEmpty else { return nil }
        return rasterize(compose(grays, gap: gapDots, margin: endMarginDots, height: printableHeight),
                         cellWidths: grays.map(\.width), gap: gapDots, margin: endMarginDots)
    }

    /// Convenience: an optional leading image plus text, as two cells.
    public func render(text: String, fontName: String = "Helvetica",
                       sizing: SizingMode = .fitText, imageURL: URL? = nil,
                       mergeGapDots: Int = 24) -> RenderedLabel? {
        var cells: [LabelCell] = []
        if let url = imageURL { cells.append(.image(url.path)) }
        if !text.isEmpty { cells.append(LabelCell(kind: .text, text: text, fontName: fontName, sizing: sizing)) }
        return render(cells: cells, gapDots: mergeGapDots)
    }

    // MARK: - Per-cell

    private func renderCell(_ cell: LabelCell, lineSpacing: CGFloat, fillFraction: CGFloat) -> Gray? {
        let H = printableHeight
        let inverted = cell.style == .inverted
        let vFill = inverted ? min(fillFraction, 0.74) : fillFraction
        let innerH = max(1, Int(CGFloat(H) * vFill))
        let pad = inverted ? 18 : 0

        var g: Gray?
        switch cell.kind {
        case .text:
            let text = cell.text.replacingOccurrences(of: "\\n", with: "\n")
            // Normal text renders tight (no internal side padding) so cell spacing
            // alone controls the gap; page margins come from the label's end
            // margin. Inverted keeps padding — that's the box's internal inset.
            g = textGray(text, fontName: cell.fontName, sizing: cell.sizing,
                         lineSpacing: lineSpacing, fillFraction: vFill,
                         sideMarginDots: inverted ? 18 : 0)
        case .image:
            if var content = imageContent(cell, height: innerH) {
                adjustLevels(&content, brightness: cell.brightness, contrast: cell.contrast)
                g = place(cell.dithered ? floydSteinberg(content) : content, hPad: pad)
            }
        case .symbol:
            if let n = cell.symbolName, let ink = symbolInk(n) {
                g = place(scaleToHeight(ink, innerH), hPad: pad)
            }
        }
        guard var gray = g else { return nil }
        if inverted { for i in gray.px.indices { gray.px[i] = 255 - gray.px[i] } }
        return gray
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
        let asc = CTFontGetAscent(probe), desc = CTFontGetDescent(probe), cap = CTFontGetCapHeight(probe)
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

    // MARK: - Image / PDF / symbol → content bitmap of the given height

    /// Resolve an image cell's content to a grayscale bitmap of the given height,
    /// preferring embedded `imageData` over the source `imagePath`.
    private func imageContent(_ cell: LabelCell, height ih: Int) -> Gray? {
        if let d = cell.imageData { return imageContentGray(data: d, height: ih) }
        if let p = cell.imagePath { return imageContentGray(URL(fileURLWithPath: p), height: ih) }
        return nil
    }

    private func imageContentGray(_ url: URL, height ih: Int) -> Gray? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1) else { return nil }
            let box = page.getBoxRect(.mediaBox); guard box.height > 0 else { return nil }
            let scale = CGFloat(ih) / box.height
            let sW = max(1, Int((box.width * scale).rounded()))
            guard let ctx = grayContext(sW, ih) else { return nil }
            ctx.saveGState(); ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY); ctx.drawPDFPage(page); ctx.restoreGState()
            return cropHorizontally(readGray(ctx, sW, ih))
        case "svg":
            return svgGray(url, height: ih)
        default:
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            return imageContentGray(cg: cg, height: ih)
        }
    }

    /// Rasterize an SVG via NSImage into a grayscale bitmap, cropped to its ink and
    /// scaled to fill the band height (SVG viewBoxes often pad the artwork, which
    /// would otherwise print undersized on the tape). Colours are mapped to
    /// luminance (composited over white); a fully light/white opaque SVG falls back
    /// to alpha coverage so its shape still prints as ink. (CGImageSource can't
    /// decode SVG, so this uses AppKit's SVG support — the same path as the bundled
    /// icon generator.)
    private func svgGray(_ url: URL, height ih: Int) -> Gray? {
        guard let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else { return nil }
        // Render large, then crop-to-ink and scale down, so filling the band stays crisp.
        let H = max(ih, 256)
        let w = max(1, Int((img.size.width / img.size.height * CGFloat(H)).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: H,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: w, height: H)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: H))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }
        let spp = rep.samplesPerPixel, rb = rep.bytesPerRow
        var px = [UInt8](repeating: 255, count: w * H)
        var opaque = 0, dark = 0
        for r in 0..<H {
            for c in 0..<w {
                let o = r * rb + c * spp
                let a = Int(data[o + spp - 1])
                guard a > 40 else { continue }
                opaque += 1
                let lum = (Int(data[o]) * 54 + Int(data[o + 1]) * 183 + Int(data[o + 2]) * 19) >> 8
                let g = 255 - ((255 - lum) * a / 255)   // composite over white
                px[r * w + c] = UInt8(g)
                if g < 128 { dark += 1 }
            }
        }
        if opaque > 0 && dark * 20 < opaque {   // all-but-white opaque → use alpha as ink
            for r in 0..<H {
                for c in 0..<w { px[r * w + c] = data[r * rb + c * spp + spp - 1] > 40 ? 0 : 255 }
            }
        }
        return scaleToHeight(cropToInk(Gray(width: w, height: H, px: px)), ih)
    }

    private func imageContentGray(data: Data, height ih: Int) -> Gray? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return imageContentGray(cg: cg, height: ih)
    }

    /// Apply brightness/contrast (each −1…1, 0 = none) to a grayscale bitmap before
    /// the 1-bit step, so the black/white cutoff can be tuned for line art/logos.
    private func adjustLevels(_ g: inout Gray, brightness b: Double, contrast c: Double) {
        guard b != 0 || c != 0 else { return }
        let cf = 1 + c                       // contrast factor around mid-grey
        let shift = b * 255
        for i in g.px.indices {
            let x = (Double(g.px[i]) - 128) * cf + 128 + shift
            g.px[i] = UInt8(min(255, max(0, x)))
        }
    }

    /// Floyd–Steinberg dither a grayscale bitmap to 1-bit (0/255). Run at the final
    /// dot resolution so the error diffusion matches what actually prints — gives
    /// photos the illusion of mid-tones instead of a harsh threshold.
    private func floydSteinberg(_ g: Gray) -> Gray {
        let w = g.width, h = g.height
        var buf = g.px.map(Int.init)
        var out = [UInt8](repeating: 255, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let new = buf[i] < 128 ? 0 : 255
                out[i] = UInt8(new)
                let err = buf[i] - new
                if x + 1 < w { buf[i + 1] += err * 7 / 16 }
                if y + 1 < h {
                    if x > 0 { buf[i + w - 1] += err * 3 / 16 }
                    buf[i + w] += err * 5 / 16
                    if x + 1 < w { buf[i + w + 1] += err / 16 }
                }
            }
        }
        return Gray(width: w, height: h, px: out)
    }

    private func imageContentGray(cg: CGImage, height ih: Int) -> Gray? {
        let sW = max(1, Int((CGFloat(cg.width) * CGFloat(ih) / CGFloat(cg.height)).rounded()))
        guard let ctx = grayContext(sW, ih) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: sW, height: ih))
        return cropHorizontally(readGray(ctx, sW, ih))
    }

    /// An image cell's content, downsized to the printable height, as a grayscale
    /// PNG. Used to embed (bake) images into saved labels so they no longer depend
    /// on the original file. Returns nil for non-image cells or unreadable sources.
    public func downsizedImagePNG(for cell: LabelCell) -> Data? {
        guard cell.kind == .image, let gray = imageContent(cell, height: printableHeight),
              let cg = grayToCGImage(gray) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private func grayToCGImage(_ g: Gray) -> CGImage? {
        guard let ctx = grayContext(g.width, g.height), let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * g.height)
        for r in 0..<g.height { for c in 0..<g.width { ptr[r * ctx.bytesPerRow + c] = g.px[r * g.width + c] } }
        return ctx.makeImage()
    }

    /// The symbol's tight ink bitmap. Prefers a bundled Bootstrap icon (pre-
    /// rasterized grayscale PNG); falls back to SF Symbols so any pre-existing
    /// SF-named cells still render.
    private func symbolInk(_ name: String) -> Gray? {
        if let cg = BootstrapIcons.image(named: name) {
            let w = cg.width, h = cg.height
            guard let ctx = grayContext(w, h) else { return nil }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return cropToInk(readGray(ctx, w, h))
        }
        return sfSymbolInk(name)
    }

    /// SF Symbols fallback (legacy). Uses the alpha channel as the glyph shape so
    /// it's appearance-independent.
    private func sfSymbolInk(_ name: String) -> Gray? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 240, weight: .regular)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let sym = base.withSymbolConfiguration(cfg) else { return nil }
        let w = max(1, Int(sym.size.width.rounded())), h = max(1, Int(sym.size.height.rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        sym.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }
        let spp = rep.samplesPerPixel, rowBytes = rep.bytesPerRow
        var px = [UInt8](repeating: 255, count: w * h)
        for r in 0..<h {
            for c in 0..<w where data[r * rowBytes + c * spp + (spp - 1)] > 40 { px[r * w + c] = 0 }
        }
        return cropToInk(Gray(width: w, height: h, px: px))
    }

    /// Scale a grayscale bitmap to an exact height, preserving aspect.
    private func scaleToHeight(_ g: Gray, _ targetH: Int) -> Gray {
        if g.height == targetH { return g }
        guard let src = grayContext(g.width, g.height) else { return g }
        let sp = src.data!.bindMemory(to: UInt8.self, capacity: src.bytesPerRow * g.height)
        for r in 0..<g.height { for c in 0..<g.width { sp[r * src.bytesPerRow + c] = g.px[r * g.width + c] } }
        guard let img = src.makeImage() else { return g }
        let tW = max(1, Int((CGFloat(g.width) * CGFloat(targetH) / CGFloat(g.height)).rounded()))
        guard let dst = grayContext(tW, targetH) else { return g }
        dst.interpolationQuality = .high
        dst.draw(img, in: CGRect(x: 0, y: 0, width: tW, height: targetH))
        return readGray(dst, tW, targetH)
    }

    /// Centre a content bitmap (height ≤ printableHeight) in a full-height white
    /// canvas with `hPad` columns of padding on each side.
    private func place(_ content: Gray, hPad: Int) -> Gray {
        let H = printableHeight
        let w = content.width + 2 * hPad
        var px = [UInt8](repeating: 255, count: w * H)
        let yoff = (H - content.height) / 2
        for r in 0..<content.height {
            let dr = r + yoff; guard dr >= 0, dr < H else { continue }
            for c in 0..<content.width { px[dr * w + (c + hPad)] = content.px[r * content.width + c] }
        }
        return Gray(width: w, height: H, px: px)
    }

    // MARK: - Compose + rasterize

    private func compose(_ parts: [Gray], gap: Int, margin: Int, height H: Int) -> Gray {
        let inner = parts.map(\.width).reduce(0, +) + gap * max(0, parts.count - 1)
        let total = max(1, inner + 2 * margin)
        var px = [UInt8](repeating: 255, count: total * H)
        var x = margin
        for (i, p) in parts.enumerated() {
            for r in 0..<H { for c in 0..<p.width { px[r * total + (x + c)] = p.px[r * p.width + c] } }
            x += p.width + (i < parts.count - 1 ? gap : 0)
        }
        return Gray(width: total, height: H, px: px)
    }

    private func rasterize(_ g: Gray, cellWidths: [Int], gap: Int, margin: Int) -> RenderedLabel? {
        let H = g.height
        guard let ctx = grayContext(g.width, H), let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * H)
        // Threshold the preview the same way the printer does (1-bit at 128), so the
        // on-screen preview shows exactly what will print — not a smoother grayscale.
        for r in 0..<H { for c in 0..<g.width { ptr[r * ctx.bytesPerRow + c] = g.px[r * g.width + c] < 128 ? 0 : 255 } }
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
        return RenderedLabel(rows: flipLength ? rows.reversed() : rows, preview: preview,
                             cellWidths: cellWidths, gapDots: gap, marginDots: margin)
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

    private func cropToInk(_ g: Gray, threshold: UInt8 = 200) -> Gray {
        var lo = g.width, hi = -1, top = g.height, bot = -1
        for r in 0..<g.height {
            for c in 0..<g.width where g.px[r * g.width + c] < threshold {
                lo = min(lo, c); hi = max(hi, c); top = min(top, r); bot = max(bot, r)
            }
        }
        guard hi >= lo, bot >= top else { return g }
        let w = hi - lo + 1, h = bot - top + 1
        var px = [UInt8](repeating: 255, count: w * h)
        for r in 0..<h { for c in 0..<w { px[r * w + c] = g.px[(top + r) * g.width + (lo + c)] } }
        return Gray(width: w, height: h, px: px)
    }

    private func cropHorizontally(_ g: Gray, threshold: UInt8 = 200) -> Gray {
        var lo = g.width, hi = -1
        for c in 0..<g.width {
            for r in 0..<g.height where g.px[r * g.width + c] < threshold { lo = min(lo, c); hi = max(hi, c); break }
        }
        guard hi >= lo else { return g }
        let w = hi - lo + 1
        var px = [UInt8](repeating: 255, count: w * g.height)
        for r in 0..<g.height { for c in 0..<w { px[r * w + c] = g.px[r * g.width + (lo + c)] } }
        return Gray(width: w, height: g.height, px: px)
    }
}
#endif
