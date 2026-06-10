import Foundation
import SwiftData
import PTouchKit

/// A persisted (and, with the iCloud capability, CloudKit-synced) saved label.
///
/// CloudKit-compatible by construction: every stored property has a default and
/// there are no unique constraints. The cell list is stored as JSON in
/// `cellsData` so SwiftData/CloudKit only sees a plain `Data` attribute.
@Model
final class SavedLabelModel {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var cellsData: Data = Data()
    var cellSpacingMM: Double = 2.7

    /// The decoded cells (not itself persisted; backed by `cellsData`).
    var cells: [LabelCell] {
        get { (try? JSONDecoder().decode([LabelCell].self, from: cellsData)) ?? [] }
        set { cellsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(name: String, cells: [LabelCell], cellSpacingMM: Double = 2.7) {
        self.name = name
        self.cellsData = (try? JSONEncoder().encode(cells)) ?? Data()
        self.cellSpacingMM = cellSpacingMM
    }
}
