import Foundation

/// How text is sized to the printable height.
public enum SizingMode: String, Sendable, CaseIterable, Codable {
    case fitText    // largest size that fits this specific text's ink (default)
    case capHeight  // consistent cap-height sizing regardless of glyphs
}

/// Normal (content on tape) or inverted (solid box with knocked-out content).
public enum CellStyle: String, Sendable, CaseIterable, Codable {
    case normal, inverted
}

/// One segment of a label, composed left-to-right. A label is `[LabelCell]`;
/// the common case is a single text cell. Flat + Codable so it persists cleanly
/// (SwiftData/JSON) and is platform-agnostic (usable by a future iOS client).
public struct LabelCell: Identifiable, Sendable, Codable, Hashable {
    public enum Kind: String, Sendable, CaseIterable, Codable { case text, image, symbol }

    public var id: UUID
    public var kind: Kind
    public var text: String
    public var fontName: String
    public var sizing: SizingMode
    public var imagePath: String?
    /// Embedded, already-downsized pixel image (PNG). When set, the renderer uses
    /// this instead of `imagePath`, so saved labels are self-contained (no source
    /// file needed) and sync across devices. Persisted/saved labels bake their
    /// image cells into this; the live editor may still reference `imagePath`.
    public var imageData: Data?
    public var symbolName: String?
    public var style: CellStyle
    /// Image cells only: dither (Floyd–Steinberg) to 1-bit instead of a hard
    /// threshold — better for photos. Ignored for text/symbol cells.
    public var dithered: Bool
    /// Image cells only: tone adjustments (each −1…1, 0 = none) applied to the
    /// grayscale before the 1-bit step, to tune where black/white falls.
    public var brightness: Double
    public var contrast: Double

    public init(id: UUID = UUID(), kind: Kind = .text, text: String = "",
                fontName: String = "Helvetica", sizing: SizingMode = .fitText,
                imagePath: String? = nil, imageData: Data? = nil, symbolName: String? = nil,
                style: CellStyle = .normal, dithered: Bool = false,
                brightness: Double = 0, contrast: Double = 0) {
        self.id = id; self.kind = kind; self.text = text; self.fontName = fontName
        self.sizing = sizing; self.imagePath = imagePath; self.imageData = imageData
        self.symbolName = symbolName; self.style = style; self.dithered = dithered
        self.brightness = brightness; self.contrast = contrast
    }

    // Tolerant decoding so labels saved by earlier versions (without newer keys
    // like `dithered`/`imageData`) still load. Encoding stays synthesized.
    enum CodingKeys: String, CodingKey {
        case id, kind, text, fontName, sizing, imagePath, imageData, symbolName, style
        case dithered, brightness, contrast
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? "Helvetica"
        sizing = try c.decodeIfPresent(SizingMode.self, forKey: .sizing) ?? .fitText
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        symbolName = try c.decodeIfPresent(String.self, forKey: .symbolName)
        style = try c.decodeIfPresent(CellStyle.self, forKey: .style) ?? .normal
        dithered = try c.decodeIfPresent(Bool.self, forKey: .dithered) ?? false
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
    }

    public static func text(_ s: String, font: String = "Helvetica") -> LabelCell {
        LabelCell(kind: .text, text: s, fontName: font)
    }
    public static func image(_ path: String) -> LabelCell {
        LabelCell(kind: .image, imagePath: path)
    }
    public static func symbol(_ name: String) -> LabelCell {
        LabelCell(kind: .symbol, symbolName: name)
    }
}
