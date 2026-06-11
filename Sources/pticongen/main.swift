// pticongen — dev-only one-time generator.
//
// Rasterizes a directory of (monochrome) SVG icons into tightly-cropped grayscale
// PNGs that PTouchKit ships and renders. Used to convert the MIT-licensed Bootstrap
// Icons set into `Sources/PTouchKit/Resources/icons/*.png`. Not a shipped product.
//
// Usage:
//   swift run pticongen <svg-dir> <out-png-dir> [height]
//
// Each icon is drawn via its alpha channel (appearance-independent — the SVGs fill
// with `currentColor`, which renders as a template), so the shape comes out solid
// black on white regardless of how the SVG declares colour. This mirrors the
// alpha-channel technique in LabelRenderer.symbolInk.

#if os(macOS)
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { fail("usage: pticongen <svg-dir> <out-png-dir> [height]") }
let svgDir = URL(fileURLWithPath: args[0], isDirectory: true)
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
let H = args.count >= 3 ? max(16, Int(args[2]) ?? 160) : 160

let fm = FileManager.default
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
guard let entries = try? fm.contentsOfDirectory(at: svgDir, includingPropertiesForKeys: nil) else {
    fail("cannot read \(svgDir.path)")
}
let svgs = entries.filter { $0.pathExtension.lowercased() == "svg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !svgs.isEmpty else { fail("no .svg files in \(svgDir.path)") }

/// Render an SVG to a tightly-cropped grayscale CGImage (0 = ink, 255 = white).
func rasterize(_ url: URL, height: Int) -> CGImage? {
    guard let img = NSImage(contentsOf: url) else { return nil }
    let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1
    let w = max(1, Int((aspect * CGFloat(height)).rounded()))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: w, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: w, height: height))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.bitmapData else { return nil }
    let spp = rep.samplesPerPixel, rb = rep.bytesPerRow

    // Coverage from alpha → grayscale, then crop to ink.
    var lo = w, hi = -1, top = height, bot = -1
    var gray = [UInt8](repeating: 255, count: w * height)
    for r in 0..<height {
        for c in 0..<w {
            let a = data[r * rb + c * spp + (spp - 1)]
            if a > 40 { gray[r * w + c] = 255 - a; lo = min(lo, c); hi = max(hi, c); top = min(top, r); bot = max(bot, r) }
        }
    }
    guard hi >= lo, bot >= top else { return nil }   // empty
    let cw = hi - lo + 1, ch = bot - top + 1
    guard let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ch)
    for r in 0..<ch { for c in 0..<cw { p[r * ctx.bytesPerRow + c] = gray[(top + r) * w + (lo + c)] } }
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

var ok = 0, skipped = 0
for svg in svgs {
    let name = svg.deletingPathExtension().lastPathComponent
    guard let cg = rasterize(svg, height: H) else { skipped += 1; continue }
    if writePNG(cg, to: outDir.appendingPathComponent(name + ".png")) { ok += 1 } else { skipped += 1 }
}
print("pticongen: wrote \(ok) PNGs (\(H)px tall) to \(outDir.path); skipped \(skipped)")
#else
print("pticongen requires macOS."); exit(1)
#endif
