import Foundation

public struct PrintOptions: Sendable {
    public var compress = true
    public var chaining = false        // feed/cut at end of each label
    public var autoCut = false         // on PT-P300BT: print the label boundary
    public var endMarginDots: UInt16 = 0
    public init() {}
}

/// Drives a full print: configure for the loaded tape, stream the raster, print.
/// `rows` are raster lines (each `bufferWidth/8` bytes, MSB-first, bit 1 = black),
/// e.g. from `LabelRenderer`. `status` is a fresh status read for the tape.
public enum PrintJob {
    @discardableResult
    public static func send(rows: [[UInt8]],
                            status: PrinterStatus,
                            to transport: PrinterTransport,
                            options: PrintOptions = .init()) throws -> PrinterStatus? {
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

        // Print and feed.
        try transport.send(PTouchCommand.printAndFeed(true))

        // Best-effort: read the status the printer returns after printing.
        let reply = try transport.read(32, timeout: 8)
        return PrinterStatus(reply)
    }
}
