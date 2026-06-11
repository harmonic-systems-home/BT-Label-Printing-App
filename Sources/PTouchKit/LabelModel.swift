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

    public init(id: UUID = UUID(), kind: Kind = .text, text: String = "",
                fontName: String = "Helvetica", sizing: SizingMode = .fitText,
                imagePath: String? = nil, imageData: Data? = nil, symbolName: String? = nil,
                style: CellStyle = .normal) {
        self.id = id; self.kind = kind; self.text = text; self.fontName = fontName
        self.sizing = sizing; self.imagePath = imagePath; self.imageData = imageData
        self.symbolName = symbolName; self.style = style
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
