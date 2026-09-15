import Foundation

public struct PrintOptions: Sendable {
    public var compress = true
    public var chaining = false        // feed/cut at end of each label
    public var autoCut = false         // on PT-P300BT: print the label boundary
    public var endMarginDots: UInt16 = 0
    public var completionTimeout: TimeInterval? = nil   // nil = scale with label length
    public init() {}
}

public enum PrintError: Error, CustomStringConvertible {
    case printerError(PrinterStatus)
    case printerTurnedOff
    case completionTimeout

    public var description: String {
        switch self {
        case .printerError(let s):
            let names = s.errorNames
            return "Printer reported an error: "
                + (names.isEmpty ? String(format: "0x%02x%02x", s.error1, s.error2) : names.joined(separator: ", "))
        case .printerTurnedOff: return "The printer turned off before the label finished printing."
        case .completionTimeout: return "Timed out waiting for the printer to finish the label."
        }
    }
}

/// Drives a full print: configure for the loaded tape, stream the raster, print.
/// `rows` are raster lines (each `bufferWidth/8` bytes, MSB-first, bit 1 = black),
/// e.g. from `LabelRenderer`. `status` is a fresh status read for the tape.
/// Returns the printer's "printing completed" status; throws `PrintError` if the
/// printer reports an error or turns off mid-job.
public enum PrintJob {
    @discardableResult
    public static func send(rows: [[UInt8]],
                            status: PrinterStatus,
                            to transport: PrinterTransport,
                            options: PrintOptions = .init()) throws -> PrinterStatus {
        let rasterLines = rows.count
        let lengthMM = status.raw.count > 17 ? status.raw[17] : 0

        // Configure (mirrors the known-good reset + configure sequence).
        try transport.send(PTouchCommand.invalidate(64))
        try transport.send(PTouchCommand.initialize)
        try transport.send(PTouchCommand.switchMode(raster: true))
        try transport.send(PTouchCommand.printInformation(mediaType: status.mediaType,
                                                           widthMM: status.mediaWidthMM,
                                                           lengthMM: lengthMM,
                                                           rasterLines: rasterLines))
        try transport.send(PTouchCommand.advancedMode(chaining: options.chaining))
        try transport.send(PTouchCommand.variousMode(autoCut: options.autoCut))
        try transport.send(PTouchCommand.feedAmount(dots: options.endMarginDots))
        try transport.send(PTouchCommand.compression(options.compress))

        // Raster payload.
        try transport.send(RasterEncoder.encode(rows: rows, compress: options.compress))

        // Print and feed, then wait for the job to finish. The first reply is only a
        // "printing" phase change; errors such as low battery can arrive after it.
        try transport.send(PTouchCommand.printAndFeed(true))
        let timeout = options.completionTimeout ?? completionTimeout(rasterLines: rasterLines)
        return try waitForCompletion(on: transport, timeout: timeout)
    }

    /// Generous bound on print time: a fixed allowance plus tape at ~10 mm/s
    /// (0.149 mm per raster line), well below the printer's rated speed.
    static func completionTimeout(rasterLines: Int) -> TimeInterval {
        15 + Double(rasterLines) * 0.149 / 10
    }

    /// Reads 32-byte status frames (reassembling partial reads) until the printer
    /// reports the print completed. Throws on an error or power-off frame, or when
    /// `timeout` elapses first.
    static func waitForCompletion(on transport: PrinterTransport,
                                  timeout: TimeInterval) throws -> PrinterStatus {
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8]()
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw PrintError.completionTimeout }
            buffer += try transport.read(32 - buffer.count, timeout: min(remaining, 1))
            guard let frame = PrinterStatus(buffer) else { continue }
            buffer.removeAll()
            if frame.hasError || frame.statusKind == .errorOccurred {
                throw PrintError.printerError(frame)
            }
            switch frame.statusKind {
            case .printingCompleted: return frame
            case .turnedOff: throw PrintError.printerTurnedOff
            default: continue   // phase change, notification (cover), etc.
            }
        }
    }
}
