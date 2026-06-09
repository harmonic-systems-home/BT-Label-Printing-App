import Foundation

public enum TransportError: Error, CustomStringConvertible {
    case bluetoothUnavailable
    case deviceNotFound(String)
    case openFailed(String)
    case notConnected
    case writeFailed
    case statusTimeout

    public var description: String {
        switch self {
        case .bluetoothUnavailable:
            return "Could not enumerate paired Bluetooth devices (Bluetooth off, or "
                + "this process lacks Bluetooth permission)."
        case .deviceNotFound(let n): return "No paired device whose name contains \"\(n)\"."
        case .openFailed(let m): return "Failed to open the printer channel: \(m)"
        case .notConnected: return "Not connected to a printer."
        case .writeFailed: return "Failed to write to the printer channel."
        case .statusTimeout: return "Timed out waiting for the printer's status reply."
        }
    }
}

/// Transport abstraction so the protocol/rendering layers stay platform-agnostic.
/// macOS provides `RFCOMMTransport` (Bluetooth Classic / SPP). An iOS transport
/// would slot in here if a path ever becomes available (see ARCHITECTURE.md).
public protocol PrinterTransport: AnyObject {
    /// Connect to the first paired device whose Bluetooth name contains `nameMatch`.
    func connect(nameMatch: String, timeout: TimeInterval) throws
    /// Send raw bytes to the printer.
    func send(_ bytes: [UInt8]) throws
    /// Read up to `count` bytes, waiting up to `timeout`. May return fewer.
    func read(_ count: Int, timeout: TimeInterval) throws -> [UInt8]
    /// Close the channel.
    func disconnect()
}

public extension PrinterTransport {
    /// Convenience: send an init + status request and decode the reply.
    func queryStatus(timeout: TimeInterval = 5) throws -> PrinterStatus {
        try send(PTouchCommand.invalidate())
        try send(PTouchCommand.initialize)
        try send(PTouchCommand.statusRequest)
        let reply = try read(32, timeout: timeout)
        guard let status = PrinterStatus(reply) else { throw TransportError.statusTimeout }
        return status
    }
}
