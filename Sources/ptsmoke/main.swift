import Foundation
import PTouchKit

// Smoke test: connect to the printer over Bluetooth and read its live status.
// Proves the Swift transport + protocol decode work end-to-end against hardware.
//
//   swift run ptsmoke [name-substring]   (default: PT-P300)

#if os(macOS)
let name = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "PT-P300"
let transport = RFCOMMTransport()

do {
    FileHandle.standardError.write("Connecting to \"\(name)\"...\n".data(using: .utf8)!)
    try transport.connect(nameMatch: name, timeout: 15)
    FileHandle.standardError.write("Connected. Querying status...\n".data(using: .utf8)!)
    let status = try transport.queryStatus(timeout: 6)
    transport.disconnect()

    print("STATUS: \(status.summary)")
    print("  raw: \(status.raw.map { String(format: "%02x", $0) }.joined())")
    exit(status.hasError ? 1 : 0)
} catch {
    FileHandle.standardError.write("** \(error)\n".data(using: .utf8)!)
    exit(2)
}
#else
print("ptsmoke requires macOS (IOBluetooth).")
exit(1)
#endif
