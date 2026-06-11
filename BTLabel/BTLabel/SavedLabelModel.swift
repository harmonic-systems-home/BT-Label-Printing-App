import Foundation
import SwiftData
import CryptoKit
import PTouchKit

/// A persisted (and, with the iCloud capability, CloudKit-synced) saved label —
/// either a user **favorite** or an entry in the print **history**.
///
/// CloudKit-compatible by construction: every stored property has a default and
/// there are no unique constraints. The cell list is stored as JSON in
/// `cellsData` so SwiftData/CloudKit only sees a plain `Data` attribute.
@Model
final class SavedLabelModel {
    /// "favorite" (pinned by the user) or "history" (auto-logged on print).
    enum Kind: String { case favorite, history }

    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var cellsData: Data = Data()
    var cellSpacingMM: Double = 2.7
    /// Discriminates favorites from history. Stored as a String for CloudKit.
    var kind: String = "favorite"
    /// Stable hash of the label content (cells + spacing) for dedupe.
    var contentHash: String = ""
    /// The tape this label was designed for (Brother colour codes, stored as Int
    /// for CloudKit). Default: black text (0x08) on white tape (0x01).
    var tapeColor: Int = 1
    var textColor: Int = 8

    /// The decoded cells (not itself persisted; backed by `cellsData`).
    var cells: [LabelCell] {
        get { (try? JSONDecoder().decode([LabelCell].self, from: cellsData)) ?? [] }
        set { cellsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var isFavorite: Bool { kind == Kind.favorite.rawValue }

    init(name: String, cells: [LabelCell], cellSpacingMM: Double = 2.7,
         kind: Kind = .favorite, tapeColor: Int = 1, textColor: Int = 8) {
        self.name = name
        self.cellsData = (try? JSONEncoder().encode(cells)) ?? Data()
        self.cellSpacingMM = cellSpacingMM
        self.kind = kind.rawValue
        self.contentHash = SavedLabelModel.hash(cells: cells, spacingMM: cellSpacingMM)
        self.tapeColor = tapeColor
        self.textColor = textColor
    }

    /// Stable content fingerprint used to dedupe identical labels (independent of
    /// id/date, and stable across launches/devices so synced history dedupes too).
    static func hash(cells: [LabelCell], spacingMM: Double) -> String {
        var data = (try? JSONEncoder().encode(cells)) ?? Data()
        data.append(contentsOf: "|\(Int((spacingMM * 100).rounded()))".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// App-wide settings persisted (and, with the iCloud capability, CloudKit-synced)
/// so the contact fields used by the /n /p /s /e tokens follow the user across
/// devices and survive restarts. A single instance is kept; `updatedAt` lets the
/// most recently edited copy win if sync ever produces more than one.
///
/// CloudKit-compatible by construction: every property has a default and there
/// are no unique constraints.
@Model
final class AppSettings {
    var contactName: String = ""
    var contactPhone: String = ""
    var contactStreet: String = ""
    var contactEmail: String = ""
    var updatedAt: Date = Date()

    init() {}
}
