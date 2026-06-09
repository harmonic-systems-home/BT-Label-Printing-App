import Foundation

/// Byte builders for the Brother P-touch raster command set.
///
/// These are the documented command opcodes from Brother's public "Raster
/// Command Reference" (functional protocol facts), implemented here independently
/// in Swift. No third-party source is incorporated.
public enum PTouchCommand {
    /// Clear any partially-received command (send before initialise).
    public static func invalidate(_ count: Int = 100) -> [UInt8] {
        Array(repeating: 0x00, count: count)
    }

    /// `ESC @` — initialise / reset the printer's mode and settings.
    public static let initialize: [UInt8] = [0x1B, 0x40]

    /// `ESC i S` — request a 32-byte status reply.
    public static let statusRequest: [UInt8] = [0x1B, 0x69, 0x53]

    /// `ESC i a {n}` — select command mode (1 == raster).
    public static func switchMode(raster: Bool = true) -> [UInt8] {
        [0x1B, 0x69, 0x61, raster ? 0x01 : 0x00]
    }

    /// `ESC i z` — print information: tells the printer the media and how many
    /// raster lines to expect. `rasterLines` is the label length in dots.
    public static func printInformation(mediaType: UInt8,
                                        widthMM: UInt8,
                                        lengthMM: UInt8 = 0,
                                        rasterLines: Int,
                                        firstPage: Bool = true) -> [UInt8] {
        // Validity flags: media type | media width | media length present.
        let flags: UInt8 = 0x02 | 0x04 | 0x08
        let n = UInt32(rasterLines)
        return [0x1B, 0x69, 0x7A,
                flags, mediaType, widthMM, lengthMM,
                UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF),
                UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF),
                firstPage ? 0x00 : 0x01, 0x00]
    }

    /// `ESC i M {n}` — various mode (bit6 == auto-cut).
    public static func variousMode(autoCut: Bool = false) -> [UInt8] {
        [0x1B, 0x69, 0x4D, autoCut ? 0x40 : 0x00]
    }

    /// `ESC i K {n}` — advanced mode (bit3 == no-chain / feed at end).
    public static func advancedMode(chaining: Bool = false) -> [UInt8] {
        [0x1B, 0x69, 0x4B, chaining ? 0x00 : 0x08]
    }

    /// `ESC i d {m1}{m2}` — feed (margin) amount in dots.
    public static func feedAmount(dots: UInt16) -> [UInt8] {
        [0x1B, 0x69, 0x64, UInt8(dots & 0xFF), UInt8((dots >> 8) & 0xFF)]
    }

    /// `M {n}` — compression mode (0 == none, 2 == TIFF/PackBits).
    public static func compression(_ enabled: Bool) -> [UInt8] {
        [0x4D, enabled ? 0x02 : 0x00]
    }

    /// `Z` — emit an all-zero (blank) raster line.
    public static let blankLine: [UInt8] = [0x5A]

    /// `G {len_lo}{len_hi}{data}` — transfer one raster line of payload bytes.
    public static func rasterLine(_ payload: [UInt8]) -> [UInt8] {
        let len = UInt16(payload.count)
        return [0x47, UInt8(len & 0xFF), UInt8((len >> 8) & 0xFF)] + payload
    }

    /// `0x0C` print without feeding (chaining), `0x1A` print and feed (last page).
    public static func printAndFeed(_ feed: Bool = true) -> [UInt8] { [feed ? 0x1A : 0x0C] }
}
