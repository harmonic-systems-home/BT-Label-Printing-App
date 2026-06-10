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

/// A curated set of SF Symbols offered in the symbol picker.
/// NOTE: SF Symbols are used here for the prototype; replace with a bundled
/// Apache/MIT icon set (e.g. Material Symbols) before commercial release.
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

    private let renderer = LabelRenderer()

    var rendered: RenderedLabel? { renderer.render(cells: cells) }
    var isBusy: Bool { activity == .working }

    /// A preview image for an arbitrary cell list (e.g. a favorite's thumbnail).
    func previewImage(_ cells: [LabelCell]) -> CGImage? { renderer.render(cells: cells)?.preview }
    var selectedIndex: Int? { cells.firstIndex { $0.id == selectedID } }

    init() { selectedID = cells.first?.id }

    // MARK: - Cell operations

    func addCell(_ kind: LabelCell.Kind) {
        var c = LabelCell(kind: kind)
        switch kind {
        case .text: c.text = "Text"
        case .symbol: c.symbolName = SymbolCatalog.names.first
        case .image: break
        }
        let at = (selectedIndex.map { $0 + 1 }) ?? cells.count
        cells.insert(c, at: at)
        selectedID = c.id
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
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            cells[idx].kind = .image
            cells[idx].imagePath = url.path
        }
    }

    // MARK: - Favorites

    func saveFavorite() {
        let label = cells.compactMap { $0.kind == .text ? $0.text : nil }
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        favorites.insert(SavedLabel(name: label.isEmpty ? "Label" : label, cells: cells), at: 0)
    }

    func load(_ fav: SavedLabel) {
        cells = fav.cells
        selectedID = cells.first?.id
    }

    // MARK: - Printing

    func refreshStatus() async {
        await perform("Connecting…") { t in
            let s = try t.queryStatus(timeout: 6)
            return (s, "Tape \(s.mediaWidthMM)mm — \(s.isReadyToPrint ? "ready" : "not ready")")
        }
    }

    func printCurrent() async {
        guard let rows = rendered?.rows, !rows.isEmpty else { message = "Nothing to print"; return }
        let length = Double(rows.count) * 0.149 / 10
        await perform("Printing…") { t in
            let s = try t.queryStatus(timeout: 6)
            guard s.isReadyToPrint else { return (s, "Printer not ready: \(s.summary)") }
            _ = try PrintJob.send(rows: rows, status: s, to: t)
            return (s, String(format: "Printed (~%.1f cm)", length))
        }
    }

    private func perform(_ starting: String,
                         _ op: @escaping @Sendable (RFCOMMTransport) throws -> (PrinterStatus?, String)) async {
        guard activity == .idle else { return }
        activity = .working
        message = starting
        let result = await BluetoothRunner.run(name: deviceName, op: op)
        if let s = result.status { status = s }
        message = result.message
        activity = .idle
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
            thread.stackSize = 1 << 20
            thread.name = "bluetooth.transport"
            thread.start()
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
