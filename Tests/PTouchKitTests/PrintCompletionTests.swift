import XCTest
@testable import PTouchKit

/// Scripted transport: `read` hands out the queued frames' bytes in `chunk`-sized pieces.
private final class FakeTransport: PrinterTransport {
    var pending: [UInt8]
    let chunk: Int
    var sent = [[UInt8]]()

    init(frames: [[UInt8]], chunk: Int = 32) {
        pending = frames.flatMap { $0 }
        self.chunk = chunk
    }

    func connect(nameMatch: String, timeout: TimeInterval) throws {}
    func send(_ bytes: [UInt8]) throws { sent.append(bytes) }
    func read(_ count: Int, timeout: TimeInterval) throws -> [UInt8] {
        let n = min(count, chunk, pending.count)
        let out = Array(pending.prefix(n))
        pending.removeFirst(n)
        return out
    }
    func disconnect() {}
}

/// A PT-P300BT status frame with 12mm laminated tape.
private func frame(type: UInt8, phase: UInt8 = 0, error1: UInt8 = 0, error2: UInt8 = 0) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: 32)
    b.replaceSubrange(0..<5, with: [0x80, 0x20, 0x42, 0x30, 0x72])
    b[8] = error1; b[9] = error2
    b[10] = 12; b[11] = 0x01
    b[18] = type; b[19] = phase
    return b
}

private let printingStarted = frame(type: 0x06, phase: 0x01)
private let printingCompleted = frame(type: 0x01)

final class PrintCompletionTests: XCTestCase {
    func testWaitsPastPhaseChangeForCompletion() throws {
        let t = FakeTransport(frames: [printingStarted, printingCompleted])
        let s = try PrintJob.waitForCompletion(on: t, timeout: 5)
        XCTAssertEqual(s.statusKind, .printingCompleted)
    }

    func testThrowsOnLowBatteryAfterPrintingStarts() {
        // Seen on real hardware: phase change first, then error 0x0800.
        let t = FakeTransport(frames: [printingStarted, frame(type: 0x02, phase: 0x01, error1: 0x08)])
        XCTAssertThrowsError(try PrintJob.waitForCompletion(on: t, timeout: 5)) { error in
            guard case PrintError.printerError(let s) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(s.errorNames, ["Low battery"])
            XCTAssertEqual("\(error)", "Printer reported an error: Low battery")
        }
    }

    func testReassemblesFragmentedFrames() throws {
        let t = FakeTransport(frames: [printingStarted, printingCompleted], chunk: 7)
        let s = try PrintJob.waitForCompletion(on: t, timeout: 5)
        XCTAssertEqual(s.statusKind, .printingCompleted)
    }

    func testThrowsWhenPrinterTurnsOff() {
        let t = FakeTransport(frames: [printingStarted, frame(type: 0x04)])
        XCTAssertThrowsError(try PrintJob.waitForCompletion(on: t, timeout: 5)) { error in
            guard case PrintError.printerTurnedOff = error else { return XCTFail("\(error)") }
        }
    }

    func testTimesOutWithoutCompletion() {
        let t = FakeTransport(frames: [printingStarted])
        XCTAssertThrowsError(try PrintJob.waitForCompletion(on: t, timeout: 0.2)) { error in
            guard case PrintError.completionTimeout = error else { return XCTFail("\(error)") }
        }
    }

    func testSendPrintsThenWaitsForCompletion() throws {
        let ready = try XCTUnwrap(PrinterStatus(frame(type: 0x00)))
        let t = FakeTransport(frames: [printingStarted, printingCompleted])
        let rows = [[UInt8]](repeating: [UInt8](repeating: 0, count: 16), count: 4)
        let s = try PrintJob.send(rows: rows, status: ready, to: t)
        XCTAssertEqual(t.sent.last, PTouchCommand.printAndFeed(true))
        XCTAssertEqual(s.statusKind, .printingCompleted)
        XCTAssertTrue(t.pending.isEmpty)
    }

    func testErrorNamesCoverBothErrorBytes() throws {
        let s = try XCTUnwrap(PrinterStatus(frame(type: 0x02, error1: 0x08, error2: 0x10)))
        XCTAssertEqual(s.errorNames, ["Low battery", "Cover open"])
    }
}
