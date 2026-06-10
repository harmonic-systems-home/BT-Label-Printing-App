import Foundation
import SwiftUI
import Combine
import CoreGraphics
import AppKit
import UniformTypeIdentifiers
import PTouchKit

/// A saved label design (an ordered list of cells).
struct SavedLabel: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var cells: [LabelCell]
}

/// Curated SF Symbols for the picker (prototype; swap for a bundled Apache/MIT
/// set before commercial release — license).
enum SymbolCatalog {
    static let names: [String] = [
        "clock", "alarm", "timer", "calendar", "sun.max", "moon.stars", "sparkles",
        "star.fill", "staroflife.fill", "bolt.fill", "flame.fill", "drop.fill",
        "heart.fill", "checkmark.seal.fill", "xmark.octagon.fill",
        "exclamationmark.triangle.fill", "info.circle.fill", "arrow.right", "arrow.up",
        "location.fill", "house.fill", "building.2.fill", "phone.fill", "envelope.fill",
        "wifi", "battery.100", "leaf.fill", "pawprint.fill", "gift.fill", "cart.fill",
        "bag.fill", "wrench.and.screwdriver.fill", "trash.fill", "flag.fill", "tag.fill",
        "key.fill", "lock.fill", "music.note", "camera.fill", "car.fill", "airplane",
        "cup.and.saucer.fill", "fork.knife", "cross.case.fill", "pills.fill",
    ]
}

@MainActor
final class PrinterController: ObservableObject {
    enum Activity: Equatable { case idle, working }

    @Published var deviceName = "PT-P300"
    @Published var activity: Activity = .idle
    @Published var status: PrinterStatus?
    @Published var message = "Not connected"

    // Label = ordered cells (default: one text cell).
    @Published var cells: [LabelCell] = [LabelCell(kind: .text, text: "Hello")]
    @Published var selectedID: LabelCell.ID?
    @Published var favorites: [SavedLabel] = []

    // Print run.
    @Published var copies = 1
    @Published var startIndex = 1
    @Published var totalCount = 0        // 0 == auto (startIndex + copies - 1)
    @Published var spacingMM = 4.0
    @Published var cutLine = true

    // Contact fields used by /n /p /s /e tokens (persisted).
    @Published var contactName = ""  { didSet { saveContact() } }
    @Published var contactPhone = "" { didSet { saveContact() } }
    @Published var contactStreet = "" { didSet { saveContact() } }
    @Published var contactEmail = "" { didSet { saveContact() } }

    private let renderer = LabelRenderer()

    init() {
        selectedID = cells.first?.id
        loadContact()
    }

    var isBusy: Bool { activity == .working }
    var selectedIndex: Int? { cells.firstIndex { $0.id == selectedID } }
    var effectiveCount: Int { totalCount > 0 ? totalCount : (startIndex + max(1, copies) - 1) }

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
    var rendered: RenderedLabel? { renderer.render(cells: resolvedCells(index: startIndex)) }

    /// Thumbnail for a favorite (tokens expanded with index 1).
    func previewImage(_ cells: [LabelCell]) -> CGImage? {
        renderer.render(cells: resolvedCells(index: 1, cells))?.preview
    }

    // MARK: - Cell operations

    func addCell(_ kind: LabelCell.Kind) {
        var c = LabelCell(kind: kind)
        switch kind {
        case .text: c.text = "Text"
        case .symbol: c.symbolName = SymbolCatalog.names.first
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
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            cells[idx].kind = .image; cells[idx].imagePath = url.path
        }
    }

    // MARK: - Favorites

    func saveFavorite() {
        let label = cells.compactMap { $0.kind == .text ? $0.text : nil }
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        favorites.insert(SavedLabel(name: label.isEmpty ? "Label" : label, cells: cells), at: 0)
    }

    func load(_ fav: SavedLabel) { cells = fav.cells; selectedID = cells.first?.id }

    // MARK: - Printing

    func refreshStatus() async {
        await perform("Connecting…") { t in
            let s = try t.queryStatus(timeout: 6)
            return (s, "Tape \(s.mediaWidthMM)mm — \(s.isReadyToPrint ? "ready" : "not ready")")
        }
    }

    func printCurrent() async {
        let n = max(1, copies)
        let spacing = max(0, Int((spacingMM / 0.149).rounded()))
        var all: [[UInt8]] = []
        for k in 0..<n {
            guard let r = renderer.render(cells: resolvedCells(index: startIndex + k)) else { continue }
            if !all.isEmpty {
                all += Self.blankRows(spacing)
                if cutLine { all += Self.cutLineRows(); all += Self.blankRows(spacing) }
            }
            all += r.rows
        }
        guard !all.isEmpty else { message = "Nothing to print"; return }
        let rows = all
        let length = Double(rows.count) * 0.149 / 10
        await perform(n > 1 ? "Printing \(n) labels…" : "Printing…") { t in
            let s = try t.queryStatus(timeout: 6)
            guard s.isReadyToPrint else { return (s, "Printer not ready: \(s.summary)") }
            _ = try PrintJob.send(rows: rows, status: s, to: t)
            return (s, String(format: "Printed %d (~%.1f cm)", n, length))
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

    private func perform(_ starting: String,
                         _ op: @escaping @Sendable (RFCOMMTransport) throws -> (PrinterStatus?, String)) async {
        guard activity == .idle else { return }
        activity = .working; message = starting
        let result = await BluetoothRunner.run(name: deviceName, op: op)
        if let s = result.status { status = s }
        message = result.message; activity = .idle
    }

    // MARK: - Contact persistence

    private func saveContact() {
        let d = UserDefaults.standard
        d.set(contactName, forKey: "contactName"); d.set(contactPhone, forKey: "contactPhone")
        d.set(contactStreet, forKey: "contactStreet"); d.set(contactEmail, forKey: "contactEmail")
    }
    private func loadContact() {
        let d = UserDefaults.standard
        contactName = d.string(forKey: "contactName") ?? ""
        contactPhone = d.string(forKey: "contactPhone") ?? ""
        contactStreet = d.string(forKey: "contactStreet") ?? ""
        contactEmail = d.string(forKey: "contactEmail") ?? ""
    }
}

private struct BTResult: Sendable { let status: PrinterStatus?; let message: String }

private enum BluetoothRunner {
    static func run(name: String,
                    op: @escaping @Sendable (RFCOMMTransport) throws -> (PrinterStatus?, String)) async -> BTResult {
        await withCheckedContinuation { (cont: CheckedContinuation<BTResult, Never>) in
            let thread = Thread {
                let t = RFCOMMTransport()
                do {
                    try t.connect(nameMatch: name, timeout: 15)
                    let (s, msg) = try op(t)
                    t.disconnect()
                    cont.resume(returning: BTResult(status: s, message: msg))
                } catch {
                    t.disconnect()
                    cont.resume(returning: BTResult(status: nil, message: "\(error)"))
                }
            }
            thread.stackSize = 1 << 20; thread.name = "bluetooth.transport"; thread.start()
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

enum TapeColor {
    static func color(_ code: UInt8) -> Color {
        switch code {
        case 0x01: return .white
        case 0x04: return .red
        case 0x05: return .blue
        case 0x06: return .yellow
        case 0x07: return .green
        case 0x08: return .black
        case 0x03, 0x09: return Color(white: 0.95)
        default: return .gray
        }
    }
}
