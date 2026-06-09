import Foundation
import PTouchKit

// Print a single line of text on the printer, from Swift end-to-end.
//
//   swift run ptprint "Hello from Swift"
//   swift run ptprint "Text" --flip-length --flip-width   (orientation fixes)

#if os(macOS)
var args = Array(CommandLine.arguments.dropFirst())
var flipLength = false, flipWidth = false, name = "PT-P300"
var text = "Hello from Swift"
var i = 0
var sawText = false
while i < args.count {
    switch args[i] {
    case "--flip-length": flipLength = true
    case "--flip-width": flipWidth = true
    case "--name": i += 1; if i < args.count { name = args[i] }
    default: if !sawText { text = args[i]; sawText = true }
    }
    i += 1
}

func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
let transport = RFCOMMTransport()

do {
    err("Connecting to \"\(name)\"...")
    try transport.connect(nameMatch: name, timeout: 15)
    let status = try transport.queryStatus(timeout: 6)
    err("Status: \(status.summary)")
    guard status.isReadyToPrint else {
        err("** Printer not ready (has error or wrong phase). Aborting.")
        transport.disconnect(); exit(1)
    }

    let renderer = LabelRenderer(flipLength: flipLength, flipWidth: flipWidth)
    guard let rendered = renderer.render(text: text) else {
        err("** Failed to render text."); transport.disconnect(); exit(3)
    }
    let rows = rendered.rows
    err("Rendering \"\(text)\" -> \(rows.count) raster lines (~\(String(format: "%.1f", Double(rows.count) * 0.149 / 10)) cm).")

    let result = try PrintJob.send(rows: rows, status: status, to: transport)
    if let r = result { err("Post-print status: \(r.summary)") }
    transport.disconnect()
    err("Done.")
    exit(0)
} catch {
    err("** \(error)")
    transport.disconnect()
    exit(2)
}
#else
print("ptprint requires macOS.")
exit(1)
#endif
