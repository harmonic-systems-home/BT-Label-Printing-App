import Foundation
import SwiftUI
import Combine
import CoreGraphics
import AppKit
import UniformTypeIdentifiers
import PTouchKit

/// A saved label design.
struct LabelFavorite: Identifiable, Hashable, Codable {
    var id = UUID()
    var text: String
    var fontName: String
    var sizing: SizingMode = .fitText
    var imagePath: String?
}

/// Bridges the SwiftUI UI to PTouchKit. Bluetooth work runs on a dedicated
/// thread (the IOBluetooth transport pumps its own run loop), with results
/// hopped back to the main actor.
@MainActor
final class PrinterController: ObservableObject {
    enum Activity: Equatable { case idle, working }

    @Published var deviceName = "PT-P300"
    @Published var activity: Activity = .idle
    @Published var status: PrinterStatus?
    @Published var message = "Not connected"

    // Editor state
    @Published var text = "Hello"
    @Published var fontName = "Helvetica"
    @Published var sizing: SizingMode = .fitText
    @Published var imageURL: URL?
    @Published var mergeGap: Int = 24
    @Published var favorites: [LabelFavorite] = []

    private let renderer = LabelRenderer()

    /// Live preview image + raster rows for the current text/font/image.
    var rendered: RenderedLabel? {
        renderer.render(text: text, fontName: fontName, sizing: sizing,
                        imageURL: imageURL, mergeGapDots: mergeGap)
    }

    var isBusy: Bool { activity == .working }

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

    func saveFavorite() {
        guard !text.isEmpty || imageURL != nil else { return }
        favorites.insert(LabelFavorite(text: text, fontName: fontName, sizing: sizing,
                                       imagePath: imageURL?.path), at: 0)
    }

    func load(_ fav: LabelFavorite) {
        text = fav.text; fontName = fav.fontName; sizing = fav.sizing
        imageURL = fav.imagePath.map { URL(fileURLWithPath: $0) }
    }

    func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { imageURL = panel.url }
    }

    func clearImage() { imageURL = nil }

    // MARK: - Bluetooth plumbing

    private func perform(_ starting: String,
                         _ op: @escaping @Sendable (RFCOMMTransport) throws -> (PrinterStatus?, String)) async {
        guard activity == .idle else { return }
        activity = .working
        message = starting
        let name = deviceName
        let result = await BluetoothRunner.run(name: name, op: op)
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

/// Map Brother tape/text colour codes to display colours (best-effort).
enum TapeColor {
    static func color(_ code: UInt8) -> Color {
        switch code {
        case 0x01: return .white
        case 0x04: return .red
        case 0x05: return .blue
        case 0x06: return .yellow
        case 0x07: return .green
        case 0x08: return .black
        case 0x03, 0x09: return Color(white: 0.95)   // clear
        default: return .gray
        }
    }
}
