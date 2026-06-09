#if os(macOS)
import Foundation
import IOBluetooth

/// macOS Bluetooth Classic (SPP / RFCOMM) transport via IOBluetooth.
///
/// The `/dev/cu.*` serial bridge is unreliable for this printer (pyserial-style
/// close doesn't drain the run loop, leaving the RFCOMM channel half-open).
/// Owning the channel directly and draining the run loop on close avoids that.
public final class RFCOMMTransport: NSObject, PrinterTransport, IOBluetoothRFCOMMChannelDelegate {
    private var channel: IOBluetoothRFCOMMChannel?
    private var rx = [UInt8]()
    private var openDone = false
    private var openStatus: IOReturn = kIOReturnError
    private var closed = false

    public override init() { super.init() }

    // Pump the run loop (delivering IOBluetooth callbacks) until `cond` or deadline.
    private func spin(until cond: () -> Bool, deadline: Date) {
        while !cond() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    public func connect(nameMatch: String, timeout: TimeInterval) throws {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            throw TransportError.bluetoothUnavailable
        }
        guard let device = paired.first(where: { ($0.name ?? "").contains(nameMatch) }) else {
            throw TransportError.deviceNotFound(nameMatch)
        }

        // Resolve the Serial Port Profile RFCOMM channel via SDP (UUID 0x1101).
        var channelID: BluetoothRFCOMMChannelID = 0
        let spp = IOBluetoothSDPUUID(uuid16: 0x1101)
        func resolve() -> Bool {
            if let rec = device.getServiceRecord(for: spp) {
                var cid: BluetoothRFCOMMChannelID = 0
                if rec.getRFCOMMChannelID(&cid) == kIOReturnSuccess, cid != 0 { channelID = cid; return true }
            }
            return false
        }
        if !resolve() {
            device.performSDPQuery(nil)
            spin(until: { resolve() }, deadline: Date().addingTimeInterval(min(timeout, 6)))
        }
        if channelID == 0 { channelID = 1 }

        var ch: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess else {
            throw TransportError.openFailed(String(format: "0x%08x", result))
        }
        spin(until: { self.openDone }, deadline: Date().addingTimeInterval(timeout))
        guard openDone, openStatus == kIOReturnSuccess, let opened = ch else {
            throw TransportError.openFailed("status \(String(format: "0x%08x", openStatus))")
        }
        channel = opened
    }

    public func send(_ bytes: [UInt8]) throws {
        guard let ch = channel else { throw TransportError.notConnected }
        let mtu = Int(ch.getMTU())
        let chunkSize = mtu > 0 ? mtu : 320
        var i = 0
        while i < bytes.count {
            var seg = Array(bytes[i..<min(i + chunkSize, bytes.count)])
            if ch.writeSync(&seg, length: UInt16(seg.count)) != kIOReturnSuccess {
                throw TransportError.writeFailed
            }
            i += chunkSize
        }
    }

    public func read(_ count: Int, timeout: TimeInterval) throws -> [UInt8] {
        guard channel != nil else { throw TransportError.notConnected }
        spin(until: { self.rx.count >= count || self.closed }, deadline: Date().addingTimeInterval(timeout))
        let take = min(rx.count, count)
        let out = Array(rx.prefix(take))
        rx.removeFirst(take)
        return out
    }

    public func disconnect() {
        channel?.close()
        // Drain the run loop so bluetoothd tears the RFCOMM channel down cleanly.
        spin(until: { self.closed }, deadline: Date().addingTimeInterval(1.0))
        channel = nil
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate
    public func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        openStatus = error
        openDone = true
    }
    public func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data ptr: UnsafeMutableRawPointer!, length len: Int) {
        rx.append(contentsOf: UnsafeBufferPointer(start: ptr.assumingMemoryBound(to: UInt8.self), count: len))
    }
    public func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
        closed = true
    }
}
#endif
