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

        let spp = IOBluetoothSDPUUID(uuid16: 0x1101)
        let deadline = Date().addingTimeInterval(timeout)

        // Read the SPP RFCOMM channel ID from the device's SDP record. The cached
        // record can be stale after a printer power-cycle, so `refresh` forces a
        // fresh query (used on retries).
        func channelID(refresh: Bool) -> BluetoothRFCOMMChannelID {
            func read() -> BluetoothRFCOMMChannelID {
                guard let rec = device.getServiceRecord(for: spp) else { return 0 }
                var cid: BluetoothRFCOMMChannelID = 0
                return rec.getRFCOMMChannelID(&cid) == kIOReturnSuccess ? cid : 0
            }
            if !refresh { let c = read(); if c != 0 { return c } }
            device.performSDPQuery(nil)
            spin(until: { read() != 0 }, deadline: min(deadline, Date().addingTimeInterval(4)))
            return read()
        }

        // Retry until the deadline. The two things that make the first attempt
        // after a power-cycle fail (status 0xe00002bc): the ACL link is down, and
        // the cached SDP channel can be stale. So each attempt explicitly wakes the
        // baseband link, and retries force a fresh SDP query.
        var lastError = "unknown"
        var attempt = 0
        while Date() < deadline {
            attempt += 1
            openDone = false; openStatus = kIOReturnError; closed = false; rx.removeAll()

            // Wake the baseband (ACL) link first — after a power-cycle this re-pages
            // the printer so the RFCOMM open below succeeds on a live link.
            _ = device.openConnection()

            var cid = channelID(refresh: attempt > 1)
            if cid == 0 { cid = 1 }   // SPP channel 1 fallback

            var ch: IOBluetoothRFCOMMChannel?
            let result = device.openRFCOMMChannelAsync(&ch, withChannelID: cid, delegate: self)
            if result == kIOReturnSuccess {
                spin(until: { self.openDone }, deadline: min(deadline, Date().addingTimeInterval(8)))
                if openDone, openStatus == kIOReturnSuccess, let opened = ch {
                    channel = opened
                    return
                }
                lastError = "open status \(String(format: "0x%08x", openStatus))"
                ch?.close()
            } else {
                lastError = "openRFCOMMChannelAsync \(String(format: "0x%08x", result))"
            }
            // Run-loop-friendly backoff, then retry (fresh SDP next round).
            spin(until: { false }, deadline: Date().addingTimeInterval(0.5))
        }
        throw TransportError.openFailed("after \(attempt) attempt(s): \(lastError)")
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
