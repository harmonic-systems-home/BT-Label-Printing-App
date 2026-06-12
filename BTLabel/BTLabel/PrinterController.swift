import Foundation
import SwiftUI
import SwiftData
import Combine
import CoreGraphics
import AppKit
import UniformTypeIdentifiers
import PTouchKit

/// The bundled, MIT-licensed Bootstrap Icons set (rendered from PTouchKit's
/// pre-rasterized PNGs). The picker filters this list by name.
enum SymbolCatalog {
    static var names: [String] { BootstrapIcons.names }
    /// A friendly initial selection (falls back to the first available name).
    static var defaultName: String? {
        let names = BootstrapIcons.names
        return ["star-fill", "star", "heart-fill"].first(where: names.contains) ?? names.first
    }
}

@MainActor
final class PrinterController: ObservableObject {
    enum Activity: Equatable { case idle, working }

    @Published var deviceName = "PT-P300"
    @Published var activity: Activity = .idle
    @Published var status: PrinterStatus?
    @Published var message = "Not connected"

    // Label = ordered cells (default: one text cell) + inter-cell spacing.
    @Published var cells: [LabelCell] = [LabelCell(kind: .text, text: "Hello")]
    @Published var selectedID: LabelCell.ID?
    @Published var cellSpacingMM = 2.7

    /// Bumped to ask the text editor to take focus and select all its text (e.g. at
    /// launch, so the user can immediately type over the default label text).
    @Published var focusTextToken = 0

    // The tape this label is designed for (Brother colour codes); drives the
    // tinted preview and the print-time mismatch warning. Default: black on white.
    @Published var designTape: UInt8 = 0x01
    @Published var designText: UInt8 = 0x08
    // While true, the design tape follows the installed tape as status updates.
    // Set false once the user deliberately picks a tape (or loads a favorite).
    private var designTapeIsAuto = true

    /// Set by the view; favorites, history, and settings are persisted via
    /// SwiftData (synced if the iCloud capability is enabled). Setting it loads
    /// the contact settings.
    var modelContext: ModelContext? { didSet { loadSettings() } }

    // Print run.
    @Published var copies = 1
    @Published var startIndex = 1
    @Published var totalCount = 0        // 0 == auto (startIndex + copies - 1)
    @Published var spacingMM = 2.5
    @Published var cutLine = true

    /// Set when a print is blocked because the installed tape (freshly queried)
    /// differs from the label's design tape; drives the confirmation alert.
    @Published var pendingMismatchPrint = false
    static let mismatchSentinel = "\u{1}tape-mismatch"

    /// Free-trial print allowance (designing & favorites are always free). Once the
    /// unlock is purchased the count is ignored. Persisted locally.
    static let freePrintLimit = 5
    @Published private(set) var printsUsed = UserDefaults.standard.integer(forKey: "printsUsed")
    var freePrintsLeft: Int { max(0, Self.freePrintLimit - printsUsed) }

    // Contact fields used by /n /p /s /e tokens. Persisted via SwiftData/iCloud
    // (see AppSettings) so they sync across devices and survive restarts.
    @Published var contactName = ""  { didSet { saveContact() } }
    @Published var contactPhone = "" { didSet { saveContact() } }
    @Published var contactStreet = "" { didSet { saveContact() } }
    @Published var contactEmail = "" { didSet { saveContact() } }

    private let renderer = LabelRenderer()

    /// The persisted settings record (loaded once `modelContext` is set).
    private var settings: AppSettings?
    /// Suppresses `saveContact()` while we populate the fields from the store,
    /// so loading one field can't write empty siblings back over the store.
    private var isLoadingSettings = false

    init() {
        selectedID = cells.first?.id
        // Start a fresh strip on the most recently used tape (persisted).
        (designTape, designText) = lastKnownTape
    }

    var isBusy: Bool { activity == .working }
    var selectedIndex: Int? { cells.firstIndex { $0.id == selectedID } }
    var effectiveCount: Int { totalCount > 0 ? totalCount : (startIndex + max(1, copies) - 1) }
    var cellSpacingDots: Int { max(0, Int((cellSpacingMM / 0.149).rounded())) }

    private var todayString: String {
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        return df.string(from: Date())
    }

    func context(index: Int) -> TokenContext {
        TokenContext(index: index, count: effectiveCount, name: contactName, phone: contactPhone,
                     street: contactStreet, email: contactEmail, date: todayString)
    }

    /// Cells with text tokens expanded for the given label index.
    func resolvedCells(index: Int, _ source: [LabelCell]? = nil) -> [LabelCell] {
        let ctx = context(index: index)
        return (source ?? cells).map { cell in
            guard cell.kind == .text else { return cell }
            var c = cell; c.text = TextTokens.expand(cell.text, ctx); return c
        }
    }

    /// Live preview = the first label of the run, tokens expanded.
    var rendered: RenderedLabel? {
        renderer.render(cells: resolvedCells(index: startIndex), gapDots: cellSpacingDots)
    }

    /// Thumbnail for a favorite (tokens expanded with index 1).
    func previewImage(_ cells: [LabelCell], spacingMM: Double = 2.7) -> CGImage? {
        renderer.render(cells: resolvedCells(index: 1, cells),
                        gapDots: max(0, Int((spacingMM / 0.149).rounded())))?.preview
    }

    /// A single cell's preview image (tokens expanded, no end margins), for the
    /// interactive preview bar.
    func cellImage(_ cell: LabelCell) -> CGImage? {
        renderer.render(cells: resolvedCells(index: startIndex, [cell]), endMarginDots: 0)?.preview
    }

    // MARK: - Tape colour (design tape + tinting)

    func setDesignTape(_ p: TapePreset) { designTape = p.tape; designText = p.text; designTapeIsAuto = false }

    // Last-tape memory is per printer (keyed by device name), persisted locally.
    // (Eventually this should live in cloud storage keyed by computer + printer,
    // once remote printing lands.)
    private func tapeKey(_ field: String) -> String { "lastTape.\(field).\(deviceName)" }

    /// The most recently seen installed tape: the live status if connected,
    /// otherwise the last one we saw for this printer (persisted across launches),
    /// else black-on-white.
    var lastKnownTape: (tape: UInt8, text: UInt8) {
        if let s = status { return (s.tapeColor, s.textColor) }
        let d = UserDefaults.standard
        guard d.object(forKey: tapeKey("color")) != nil else { return (0x01, 0x08) }
        return (UInt8(clamping: d.integer(forKey: tapeKey("color"))),
                UInt8(clamping: d.integer(forKey: tapeKey("text"))))
    }

    private func rememberTape(_ tape: UInt8, _ text: UInt8) {
        let d = UserDefaults.standard
        d.set(Int(tape), forKey: tapeKey("color"))
        d.set(Int(text), forKey: tapeKey("text"))
        d.synchronize()   // flush now — quit-on-close may terminate immediately after
    }

    /// Recolour a grayscale label/cell image to a tape: ink (dark) → text colour,
    /// background (light) → tape colour. Display only — the printed raster is
    /// unchanged. Anti-aliased edges blend the two colours.
    func tinted(_ gray: CGImage, tape: UInt8, text: UInt8) -> CGImage? {
        let w = gray.width, h = gray.height
        guard w > 0, h > 0,
              let gctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        gctx.draw(gray, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let gp = gctx.data else { return nil }
        let gstride = gctx.bytesPerRow
        let g = gp.bindMemory(to: UInt8.self, capacity: gstride * h)
        let bg = TapeColor.rgb(tape), ink = TapeColor.rgb(text)
        let clear = TapeColor.isClear(tape)
        let alpha: CGImageAlphaInfo = clear ? .premultipliedLast : .noneSkipLast
        guard let octx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: alpha.rawValue),
              let op = octx.data else { return nil }
        let ostride = octx.bytesPerRow
        let o = op.bindMemory(to: UInt8.self, capacity: ostride * h)
        for y in 0..<h {
            for x in 0..<w {
                let t = Int(g[y * gstride + x])   // 0 = ink … 255 = background
                let i = y * ostride + x * 4
                if clear {
                    // Clear tape: ink keeps its colour with coverage alpha; the
                    // background is transparent so a checkerboard shows through.
                    let cov = 255 - t
                    o[i]     = UInt8(Int(ink.r) * cov / 255)
                    o[i + 1] = UInt8(Int(ink.g) * cov / 255)
                    o[i + 2] = UInt8(Int(ink.b) * cov / 255)
                    o[i + 3] = UInt8(cov)
                } else {
                    o[i]     = UInt8((Int(ink.r) * (255 - t) + Int(bg.r) * t) / 255)
                    o[i + 1] = UInt8((Int(ink.g) * (255 - t) + Int(bg.g) * t) / 255)
                    o[i + 2] = UInt8((Int(ink.b) * (255 - t) + Int(bg.b) * t) / 255)
                    o[i + 3] = 255
                }
            }
        }
        return octx.makeImage()
    }

    /// Tint a grayscale image to the label currently being edited.
    func tintedDesign(_ gray: CGImage) -> CGImage? { tinted(gray, tape: designTape, text: designText) }

    func delete(id: LabelCell.ID) {
        guard cells.count > 1 else { return }   // keep at least one cell
        cells.removeAll { $0.id == id }
        if selectedID == id { selectedID = cells.first?.id }
    }

    // MARK: - Cell operations

    func addCell(_ kind: LabelCell.Kind) {
        var c = LabelCell(kind: kind)
        switch kind {
        case .text: c.text = "Text"
        case .symbol: c.symbolName = SymbolCatalog.defaultName
        case .image: break
        }
        let at = (selectedIndex.map { $0 + 1 }) ?? cells.count
        cells.insert(c, at: at); selectedID = c.id
        if kind == .image { pickImage(for: c.id) }
    }

    func deleteSelected() {
        guard let idx = selectedIndex else { return }
        cells.remove(at: idx)
        selectedID = cells[safe: idx]?.id ?? cells.last?.id
    }

    func move(_ delta: Int) {
        guard let idx = selectedIndex else { return }
        let j = idx + delta
        guard cells.indices.contains(j) else { return }
        cells.swapAt(idx, j)
    }

    func pickImage(for id: LabelCell.ID) {
        guard let idx = cells.firstIndex(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .svg, .pdf]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            cells[idx].kind = .image; cells[idx].imagePath = url.path; cells[idx].imageData = nil
        }
    }

    /// Paste an image from the clipboard as a new image cell. The image is
    /// downsized to the printable resolution and embedded directly in the cell —
    /// nothing is written to disk and no original file is kept.
    func pasteImage() {
        guard let png = Self.pngFromPasteboard(NSPasteboard.general) else {
            message = "No image on the clipboard"; return
        }
        let downsized = renderer.downsizedImagePNG(for: LabelCell(kind: .image, imageData: png)) ?? png
        let cell = LabelCell(kind: .image, imageData: downsized)
        let at = (selectedIndex.map { $0 + 1 }) ?? cells.count
        cells.insert(cell, at: at); selectedID = cell.id
        message = "Pasted image"
    }

    private static func pngFromPasteboard(_ pb: NSPasteboard) -> Data? {
        guard let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Copy a cell to the system clipboard so it can be reused. Image and symbol
    /// cells are copied as their rasterized image (Paste re-inserts them as an
    /// image cell — usable here, in another label, or in another app); text cells
    /// are copied as plain text.
    func copyCell(_ id: LabelCell.ID) {
        guard let cell = cells.first(where: { $0.id == id }) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        switch cell.kind {
        case .text:
            pb.setString(cell.text, forType: .string)
            message = "Copied text"
        case .image, .symbol:
            guard let cg = cellImage(cell) else { message = "Nothing to copy"; return }
            pb.writeObjects([NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))])
            message = "Copied image — use Paste to reuse it"
        }
    }

    // MARK: - Favorites & History

    static let historyCap = 100

    /// A display name derived from the label's text cells.
    private func labelName(_ cells: [LabelCell]) -> String {
        let label = cells.compactMap { $0.kind == .text ? $0.text : nil }
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Label" : label
    }

    /// Bake each image cell down to its embedded pixel image so saved labels are
    /// self-contained (no source file, sync-safe). Idempotent and cheap; already-
    /// embedded cells are left as-is. The original file reference is dropped.
    private func bakeImages(_ cells: [LabelCell]) -> [LabelCell] {
        cells.map { cell in
            guard cell.kind == .image, cell.imageData == nil,
                  let png = renderer.downsizedImagePNG(for: cell) else { return cell }
            var c = cell; c.imageData = png; c.imagePath = nil; return c
        }
    }

    func saveFavorite() {
        guard let ctx = modelContext else { return }
        let baked = bakeImages(cells)
        let new = SavedLabelModel(name: labelName(baked), cells: baked,
                                  cellSpacingMM: cellSpacingMM, kind: .favorite,
                                  tapeColor: Int(designTape), textColor: Int(designText))
        new.sortIndex = (favoritesIn(nil).map(\.sortIndex).min() ?? 0) - 1   // top of top-level
        ctx.insert(new)
        try? ctx.save()
    }

    /// Promote a history entry to Favorites (copy; the history record stays).
    func saveFavorite(from item: SavedLabelModel) {
        guard let ctx = modelContext else { return }
        let new = SavedLabelModel(name: item.name, cells: item.cells,
                                  cellSpacingMM: item.cellSpacingMM, kind: .favorite,
                                  tapeColor: item.tapeColor, textColor: item.textColor)
        new.sortIndex = (favoritesIn(nil).map(\.sortIndex).min() ?? 0) - 1
        ctx.insert(new)
        try? ctx.save()
    }

    /// Record a printed label in History. Distinct by content: an identical entry
    /// is moved to the top instead of duplicated. History is capped.
    private func logHistory(cells rawCells: [LabelCell], spacingMM: Double) {
        guard let ctx = modelContext else { return }
        let cells = bakeImages(rawCells)
        let hash = SavedLabelModel.hash(cells: cells, spacingMM: spacingMM)
        let history = SavedLabelModel.Kind.history.rawValue
        let existing = try? ctx.fetch(FetchDescriptor<SavedLabelModel>(
            predicate: #Predicate { $0.kind == history && $0.contentHash == hash }))
        if let dup = existing?.first {
            dup.createdAt = Date(); try? ctx.save(); return
        }
        ctx.insert(SavedLabelModel(name: labelName(cells), cells: cells,
                                   cellSpacingMM: spacingMM, kind: .history,
                                   tapeColor: Int(designTape), textColor: Int(designText)))
        try? ctx.save()
        trimHistory(ctx)
    }

    private func trimHistory(_ ctx: ModelContext) {
        let history = SavedLabelModel.Kind.history.rawValue
        let all = (try? ctx.fetch(FetchDescriptor<SavedLabelModel>(
            predicate: #Predicate { $0.kind == history },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        guard all.count > Self.historyCap else { return }
        for item in all[Self.historyCap...] { ctx.delete(item) }
        try? ctx.save()
    }

    func load(_ fav: SavedLabelModel) {
        cells = fav.cells; cellSpacingMM = fav.cellSpacingMM; selectedID = cells.first?.id
        designTape = UInt8(clamping: fav.tapeColor); designText = UInt8(clamping: fav.textColor)
        designTapeIsAuto = false   // a favorite carries its own intended tape
    }

    func newLabel() {
        cells = [LabelCell(kind: .text, text: "Text")]
        cellSpacingMM = 2.7
        selectedID = cells.first?.id
        // A new label follows the most recently used tape again.
        designTapeIsAuto = true
        (designTape, designText) = lastKnownTape
    }

    func delete(_ fav: SavedLabelModel) {
        modelContext?.delete(fav)
        try? modelContext?.save()
    }

    // MARK: - Favorite folders

    @discardableResult
    func addFolder(parentID: UUID? = nil) -> FavoriteFolder? {
        guard let ctx = modelContext else { return nil }
        let count = (try? ctx.fetchCount(FetchDescriptor<FavoriteFolder>())) ?? 0
        let newFolder = FavoriteFolder(name: "New Folder", parentID: parentID,
                                       colorIndex: count % FolderPalette.colors.count)
        ctx.insert(newFolder)
        if let pid = parentID { folder(withID: pid)?.expanded = true }
        try? ctx.save()
        return newFolder
    }

    func renameFolder(_ folder: FavoriteFolder, _ name: String) {
        folder.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext?.save()
    }

    func toggleFolder(_ folder: FavoriteFolder) {
        folder.expanded.toggle(); try? modelContext?.save()
    }

    func setFolderColor(_ folder: FavoriteFolder, _ index: Int) {
        folder.colorIndex = index; try? modelContext?.save()
    }

    /// Delete a folder; its favorites and subfolders move up to its parent.
    func deleteFolder(_ folder: FavoriteFolder) {
        guard let ctx = modelContext else { return }
        let fid = folder.id, parent = folder.parentID
        for fav in (try? ctx.fetch(FetchDescriptor<SavedLabelModel>())) ?? [] where fav.folderID == fid {
            fav.folderID = parent
        }
        for sub in (try? ctx.fetch(FetchDescriptor<FavoriteFolder>())) ?? [] where sub.parentID == fid {
            sub.parentID = parent
        }
        ctx.delete(folder); try? ctx.save()
    }

    /// Move a favorite into a folder (nil = top level), appended at the end.
    func moveFavorite(_ fav: SavedLabelModel, toFolder folderID: UUID?) {
        fav.folderID = folderID
        fav.sortIndex = (favoritesIn(folderID).filter { $0 !== fav }.map(\.sortIndex).max() ?? -1) + 1
        try? modelContext?.save()
    }

    /// Reorder a favorite to sit just before `target`, adopting target's folder.
    func reorderFavorite(_ fav: SavedLabelModel, before target: SavedLabelModel) {
        guard fav !== target else { return }
        fav.folderID = target.folderID
        var ordered = favoritesIn(target.folderID).filter { $0 !== fav }
        guard let i = ordered.firstIndex(where: { $0 === target }) else { return }
        ordered.insert(fav, at: i)
        for (n, f) in ordered.enumerated() { f.sortIndex = Double(n) }
        try? modelContext?.save()
    }

    /// Re-parent a folder (nil = top level), guarding against cycles.
    func nestFolder(_ folder: FavoriteFolder, under parentID: UUID?) {
        guard folder.id != parentID, !wouldCycle(setting: parentID, on: folder) else { return }
        folder.parentID = parentID
        folder.sortIndex = (subfolders(parentID).filter { $0 !== folder }.map(\.sortIndex).max() ?? -1) + 1
        if let pid = parentID { self.folder(withID: pid)?.expanded = true }
        try? modelContext?.save()
    }

    /// Favorites in a container, in display order (sortIndex, then newest first).
    func favoritesIn(_ folderID: UUID?) -> [SavedLabelModel] {
        let fav = SavedLabelModel.Kind.favorite.rawValue
        let all = (try? modelContext?.fetch(FetchDescriptor<SavedLabelModel>(
            predicate: #Predicate { $0.kind == fav }))) ?? []
        return all.filter { $0.folderID == folderID }
            .sorted { ($0.sortIndex, -$0.createdAt.timeIntervalSince1970) < ($1.sortIndex, -$1.createdAt.timeIntervalSince1970) }
    }

    /// Subfolders of a folder (nil = top level), in display order.
    func subfolders(_ parentID: UUID?) -> [FavoriteFolder] {
        let all = (try? modelContext?.fetch(FetchDescriptor<FavoriteFolder>())) ?? []
        return all.filter { $0.parentID == parentID }
            .sorted { ($0.sortIndex, $0.createdAt.timeIntervalSince1970) < ($1.sortIndex, $1.createdAt.timeIntervalSince1970) }
    }

    /// True if setting `parent` as `folder`'s parent would create a cycle.
    private func wouldCycle(setting parent: UUID?, on folder: FavoriteFolder) -> Bool {
        var cur = parent
        while let id = cur {
            if id == folder.id { return true }
            cur = self.folder(withID: id)?.parentID
        }
        return false
    }

    private func folder(withID id: UUID) -> FavoriteFolder? {
        try? modelContext?.fetch(FetchDescriptor<FavoriteFolder>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Printing

    func refreshStatus() async {
        _ = await perform("Connecting…") { t in
            let s = try t.queryStatus(timeout: 6)
            let msg = String(format: "Tape %dmm · tape 0x%02X / text 0x%02X · %@",
                             s.mediaWidthMM, s.tapeColor, s.textColor, s.isReadyToPrint ? "ready" : "not ready")
            return (s, msg, true)
        }
    }

    func printCurrent(force: Bool = false) async {
        let n = max(1, copies)
        let gap = max(0, Int((spacingMM / 0.149).rounded()))
        let strip = 18   // end-margin dots at the very ends of the strip
        // Render each copy tight (no per-label end margins) and place margins
        // only at the strip ends + a small gap on each side of the cut line, so
        // the space around the line is ~2x the end margin (not ~3x).
        var all: [[UInt8]] = Self.blankRows(strip)
        var any = false
        for k in 0..<n {
            guard let r = renderer.render(cells: resolvedCells(index: startIndex + k),
                                          gapDots: cellSpacingDots, endMarginDots: 0) else { continue }
            if any {
                all += Self.blankRows(gap)
                if cutLine { all += Self.cutLineRows(); all += Self.blankRows(gap) }
            }
            all += r.rows
            any = true
        }
        guard any else { message = "Nothing to print"; return }
        all += Self.blankRows(strip)
        let rows = all
        let length = Double(rows.count) * 0.149 / 10
        let snapshotCells = cells, snapshotSpacing = cellSpacingMM
        let dTape = designTape
        let printed = await perform(n > 1 ? "Printing \(n) labels…" : "Printing…") { t in
            let s = try t.queryStatus(timeout: 6)
            guard s.isReadyToPrint else { return (s, "Printer not ready: \(s.summary)", false) }
            // Confirm the freshly-queried installed tape matches the design tape.
            if !force && s.tapeColor != dTape { return (s, Self.mismatchSentinel, false) }
            _ = try PrintJob.send(rows: rows, status: s, to: t)
            return (s, String(format: "Printed %d (~%.1f cm)", n, length), true)
        }
        if printed {
            logHistory(cells: snapshotCells, spacingMM: snapshotSpacing)
            printsUsed += 1
            UserDefaults.standard.set(printsUsed, forKey: "printsUsed")
        } else if message == Self.mismatchSentinel {
            message = "Wrong tape loaded"
            pendingMismatchPrint = true
        }
    }

    private static func blankRows(_ n: Int) -> [[UInt8]] {
        Array(repeating: [UInt8](repeating: 0, count: 16), count: max(0, n))
    }
    private static func cutLineRows() -> [[UInt8]] {
        var row = [UInt8](repeating: 0, count: 16)
        for b in 4...11 { row[b] = 0xFF }   // dots 32..95 = printable band -> vertical line
        return [row, row]
    }

    /// Runs a Bluetooth op on the dedicated thread. Returns whether the op
    /// reported success (its third tuple element), e.g. a print actually happened.
    @discardableResult
    private func perform(_ starting: String,
                         _ op: @escaping @Sendable (RFCOMMTransport) throws -> (PrinterStatus?, String, Bool)) async -> Bool {
        guard activity == .idle else { return false }
        activity = .working; message = starting
        let result = await BluetoothRunner.run(name: deviceName, op: op)
        if let s = result.status {
            status = s
            rememberTape(s.tapeColor, s.textColor)   // persist for the next launch
            // Follow the installed tape in the preview/picker until the user picks one.
            if designTapeIsAuto { designTape = s.tapeColor; designText = s.textColor }
        }
        message = result.message; activity = .idle
        return result.ok
    }

    // MARK: - Contact persistence (SwiftData / iCloud)

    /// Load the contact fields from the persisted settings (fetch-or-create).
    private func loadSettings() {
        guard let ctx = modelContext else { return }
        let all = (try? ctx.fetch(FetchDescriptor<AppSettings>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        // If sync produced more than one settings row, keep the newest and prune.
        if all.count > 1 {
            for extra in all.dropFirst() { ctx.delete(extra) }
            try? ctx.save()
        }
        let s = all.first ?? {
            let new = AppSettings(); ctx.insert(new); return new
        }()
        settings = s
        isLoadingSettings = true
        contactName = s.contactName; contactPhone = s.contactPhone
        contactStreet = s.contactStreet; contactEmail = s.contactEmail
        isLoadingSettings = false
    }

    private func saveContact() {
        guard !isLoadingSettings, let ctx = modelContext, let s = settings else { return }
        s.contactName = contactName; s.contactPhone = contactPhone
        s.contactStreet = contactStreet; s.contactEmail = contactEmail
        s.updatedAt = Date()
        try? ctx.save()
    }
}

private struct BTResult: Sendable { let status: PrinterStatus?; let message: String; let ok: Bool }

private enum BluetoothRunner {
    static func run(name: String,
                    op: @escaping @Sendable (RFCOMMTransport) throws -> (PrinterStatus?, String, Bool)) async -> BTResult {
        await withCheckedContinuation { (cont: CheckedContinuation<BTResult, Never>) in
            let thread = Thread {
                let t = RFCOMMTransport()
                do {
                    try t.connect(nameMatch: name, timeout: 15)
                    let (s, msg, ok) = try op(t)
                    t.disconnect()
                    cont.resume(returning: BTResult(status: s, message: msg, ok: ok))
                } catch {
                    t.disconnect()
                    cont.resume(returning: BTResult(status: nil, message: "\(error)", ok: false))
                }
            }
            thread.stackSize = 1 << 20; thread.name = "bluetooth.transport"; thread.start()
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

enum FolderPalette {
    static let colors: [Color] = [
        Color(red: 0.30, green: 0.55, blue: 0.90),  // blue
        Color(red: 0.30, green: 0.70, blue: 0.45),  // green
        Color(red: 0.92, green: 0.60, blue: 0.25),  // orange
        Color(red: 0.66, green: 0.45, blue: 0.86),  // purple
        Color(red: 0.88, green: 0.42, blue: 0.46),  // rose
        Color(red: 0.28, green: 0.70, blue: 0.74),  // teal
    ]
    static func color(_ index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }
}

enum TapeColor {
    /// Display RGB for a tape/text colour code. Confirmed on this unit: white tape
    /// 0x01, black tape/text 0x08, gold text 0x0A (TZe-334); the remaining colour
    /// codes are best-effort until validated against physical tapes.
    static func rgb(_ code: UInt8) -> (r: UInt8, g: UInt8, b: UInt8) {
        switch code {
        case 0x01: return (255, 255, 255)       // white
        case 0x04: return (214, 48, 49)         // red
        case 0x05: return (33, 99, 199)         // blue
        case 0x06: return (247, 214, 51)        // yellow
        case 0x07: return (40, 160, 78)         // green
        case 0x08: return (26, 26, 28)          // black
        case 0x0A: return (201, 167, 74)        // gold (text, confirmed TZe-334)
        case 0x40: return (255, 122, 26)        // fluorescent orange
        case 0x41: return (214, 247, 38)        // fluorescent yellow
        case 0x03, 0x09: return (244, 244, 246) // clear / other (light)
        default: return (142, 142, 147)         // unknown
        }
    }

    static func color(_ code: UInt8) -> Color {
        let c = rgb(code)
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// Clear/transparent tapes — shown with a checkerboard rather than a colour.
    static func isClear(_ code: UInt8) -> Bool { code == 0x03 || code == 0x09 }
}

/// A curated set of common 12 mm Brother TZe tapes as text-on-background pairs.
/// The codes follow the printer's status colour bytes; non-white entries are
/// best-effort pending validation against physical tapes.
struct TapePreset: Identifiable, Hashable {
    let name: String
    let tape: UInt8
    let text: UInt8
    var id: String { name }

    static let all: [TapePreset] = [
        .init(name: "Black on White",     tape: 0x01, text: 0x08),
        .init(name: "Black on Clear",     tape: 0x09, text: 0x08),
        .init(name: "White on Black",     tape: 0x08, text: 0x01),
        .init(name: "Gold on Black",      tape: 0x08, text: 0x0A),   // TZe-334
        .init(name: "Black on Red",       tape: 0x04, text: 0x08),
        .init(name: "White on Red",       tape: 0x04, text: 0x01),
        .init(name: "Black on Yellow",    tape: 0x06, text: 0x08),   // TZe-631
        .init(name: "Black on Green",     tape: 0x07, text: 0x08),
        .init(name: "White on Green",     tape: 0x07, text: 0x01),
        .init(name: "Black on Blue",      tape: 0x05, text: 0x08),
        .init(name: "White on Blue",      tape: 0x05, text: 0x01),
        .init(name: "Red on White",       tape: 0x01, text: 0x04),
        .init(name: "Blue on White",      tape: 0x01, text: 0x05),
        .init(name: "Black on Fl Orange", tape: 0x40, text: 0x08),
        .init(name: "Black on Fl Yellow", tape: 0x41, text: 0x08),
    ]

    /// A display name for a tape/text code pair (falls back to the tape code).
    static func name(tape: UInt8, text: UInt8) -> String {
        all.first { $0.tape == tape && $0.text == text }?.name
            ?? all.first { $0.tape == tape }?.name
            ?? String(format: "Tape 0x%02X", tape)
    }
}
