import Foundation
import PTouchKit

// Print a single line of text on the printer, from Swift end-to-end.
//
//   swift run ptprint "Hello from Swift"
//   swift run ptprint "Text" --font Menlo --flip-length --flip-width
//   swift run ptprint "Text" --preview /tmp/out.png   (render to PNG, no printer)

#if os(macOS)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

var args = Array(CommandLine.arguments.dropFirst())
var flipLength = false, flipWidth = false, name = "PT-P300", font = "Helvetica"
var previewPath: String?, imagePath: String?, symbolName: String?
var sizing: SizingMode = .fitText
var invert = false
var dither = false
var text = "Hello from Swift"
var sawText = false
var i = 0
while i < args.count {
    switch args[i] {
    case "--flip-length": flipLength = true
    case "--flip-width": flipWidth = true
    case "--invert": invert = true
    case "--dither": dither = true
    case "--name": i += 1; if i < args.count { name = args[i] }
    case "--font": i += 1; if i < args.count { font = args[i] }
    case "--preview": i += 1; if i < args.count { previewPath = args[i] }
    case "--image": i += 1; if i < args.count { imagePath = args[i] }
    case "--symbol": i += 1; if i < args.count { symbolName = args[i] }
    case "--sizing": i += 1; if i < args.count { sizing = args[i] == "cap" ? .capHeight : .fitText }
    default: if !sawText { text = args[i]; sawText = true }
    }
    i += 1
}

func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

let renderer = LabelRenderer(flipLength: flipLength, flipWidth: flipWidth)
var cells: [LabelCell] = []
if let n = symbolName { cells.append(.symbol(n)) }
if let p = imagePath { cells.append(LabelCell(kind: .image, imagePath: p, dithered: dither)) }
if !text.isEmpty {
    cells.append(LabelCell(kind: .text, text: text, fontName: font, sizing: sizing,
                           style: invert ? .inverted : .normal))
}
guard let rendered = renderer.render(cells: cells) else {
    err("** Failed to render label."); exit(3)
}
let rows = rendered.rows

// Diagnostic: vertical dot extent actually used.
var dlo = 128, dhi = -1
for line in rows { for dot in 0..<128 where (line[dot / 8] & (0x80 >> (dot % 8))) != 0 { dlo = min(dlo, dot); dhi = max(dhi, dot) } }
err("SWIFT raster: \(rows.count) lines, dot rows \(dlo)..\(dhi) = \(dhi - dlo + 1) tall (of 128)")

// Preview mode: write the readable label image to a PNG and exit (no printer).
if let path = previewPath {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        err("** Could not create PNG destination."); exit(3)
    }
    CGImageDestinationAddImage(dest, rendered.preview, nil)
    CGImageDestinationFinalize(dest)
    err("Wrote preview \(rendered.preview.width)x\(rendered.preview.height) -> \(path)")
    exit(0)
}

let transport = RFCOMMTransport()
do {
    err("Connecting to \"\(name)\"...")
    try transport.connect(nameMatch: name, timeout: 15)
    let status = try transport.queryStatus(timeout: 6)
    err("Status: \(status.summary)")
    guard status.isReadyToPrint else {
        err("** Printer not ready. Aborting."); transport.disconnect(); exit(1)
    }
    err("Rendering \"\(text)\" -> \(rows.count) raster lines (~\(String(format: "%.1f", Double(rows.count) * 0.149 / 10)) cm).")
    let result = try PrintJob.send(rows: rows, status: status, to: transport)
    if let r = result { err("Post-print status: \(r.summary)") }
    transport.disconnect()
    err("Done.")
    exit(0)
} catch {
    err("** \(error)"); transport.disconnect(); exit(2)
}
#else
print("ptprint requires macOS.")
exit(1)
#endif
