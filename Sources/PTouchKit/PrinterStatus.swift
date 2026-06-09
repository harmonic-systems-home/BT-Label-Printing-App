import Foundation

/// Decoded form of the 32-byte status reply a Brother P-touch returns to an
/// `ESC i S` (status request) or after a print command.
///
/// Field offsets follow the public Brother "Raster Command Reference" status
/// block layout. This is an independent (clean-room) implementation of that
/// documented format — no third-party source is incorporated.
public struct PrinterStatus: Sendable, Equatable {
    public enum Phase: UInt8, Sendable { case editing = 0x00, printing = 0x01, unknown = 0xFF }

    public let raw: [UInt8]            // all 32 bytes, for fields not modeled yet
    public let model: UInt8           // [4] model code (PT-P300BT == 0x72)
    public let error1: UInt8          // [8] error information 1 (bitfield)
    public let error2: UInt8          // [9] error information 2 (bitfield)
    public let mediaWidthMM: UInt8    // [10] installed tape width, millimetres
    public let mediaType: UInt8       // [11] media type (0x01 == laminated)
    public let statusType: UInt8      // [18] status type (reply / completed / phase change…)
    public let phaseType: UInt8       // [19] phase type (0 == editing, 1 == printing)
    public let phaseNumber: UInt16    // [20..21] phase number, big-endian
    public let tapeColor: UInt8       // tape colour code (see note below)
    public let textColor: UInt8       // text colour code

    public var hasError: Bool { error1 != 0 || error2 != 0 }
    public var isReadyToPrint: Bool { !hasError && statusType == 0x00 && phaseType == 0x00 }
    public var isPrinting: Bool { phaseType == 0x01 }

    /// Parse a 32-byte status block. Returns nil if the buffer is too short.
    public init?(_ bytes: [UInt8]) {
        guard bytes.count >= 32 else { return nil }
        raw = Array(bytes.prefix(32))
        model = raw[4]
        error1 = raw[8]
        error2 = raw[9]
        mediaWidthMM = raw[10]
        mediaType = raw[11]
        statusType = raw[18]
        phaseType = raw[19]
        phaseNumber = (UInt16(raw[20]) << 8) | UInt16(raw[21])
        // NOTE: the reference layout puts tape/text colour at [24]/[25]. On the
        // PT-P300BT observed here the non-zero colour codes appear at [26]/[27]
        // (e.g. white tape 0x01 / black text 0x08). We surface both regions so
        // the GUI can be calibrated against several coloured tapes later.
        tapeColor = raw[24] != 0 ? raw[24] : raw[26]
        textColor = raw[25] != 0 ? raw[25] : raw[27]
    }

    public var summary: String {
        let err = hasError ? String(format: "0x%02x%02x", error1, error2) : "none"
        return "model=0x\(String(format: "%02x", model)) "
            + "tape=\(mediaWidthMM)mm type=0x\(String(format: "%02x", mediaType)) "
            + "tapeColor=0x\(String(format: "%02x", tapeColor)) "
            + "textColor=0x\(String(format: "%02x", textColor)) "
            + "errors=\(err) "
            + (isPrinting ? "phase=printing" : (isReadyToPrint ? "phase=ready" : "phase=other"))
    }
}
