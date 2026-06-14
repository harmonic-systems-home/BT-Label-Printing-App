import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import PTouchKit

private let fontChoices = [
    "Helvetica", "Helvetica Neue", "Arial", "Avenir Next", "Gill Sans",
    "Georgia", "Times New Roman", "Menlo", "Courier New", "Marker Felt",
]

struct ContentView: View {
    @EnvironmentObject private var c: PrinterController
    @EnvironmentObject private var store: StoreManager
    @Environment(\.modelContext) private var modelContext
    // Observe AppSettings live so an incoming iCloud sync (e.g. a phone number
    // changed on another Mac) refreshes the contact fields, not just on relaunch.
    @Query(sort: \AppSettings.updatedAt, order: .reverse) private var allSettings: [AppSettings]
    @State private var showSettings = false
    @State private var didInitialFocus = false

    var body: some View {
        NavigationSplitView {
            FavoritesSidebar().navigationTitle("Labels")
        } detail: {
            VStack(spacing: 0) {
                PrinterStatusBar()
                Divider()
                ScrollView { EditorPanel().padding() }
            }
            .navigationTitle("BTLabel")
            .toolbar {
                ToolbarItem { Button { showSettings = true } label: { Image(systemName: "gearshape") } }
                ToolbarItem {
                    Button { c.showHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .help("BTLabel Help")
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(c).environmentObject(store) }
        .sheet(isPresented: $c.showHelp) { HelpView() }
        .onAppear {
            c.modelContext = modelContext
            // Focus + select the default label text so the user can just start typing.
            if !didInitialFocus { didInitialFocus = true; c.focusTextToken += 1 }
        }
        // SwiftData refreshes this @Query on local and remote (iCloud) changes;
        // fold the newest settings into the controller's contact fields.
        .onChange(of: allSettings.map(\.updatedAt)) { _, _ in
            c.adoptSettings(allSettings)
        }
    }
}

// MARK: - Status bar

struct PrinterStatusBar: View {
    @EnvironmentObject private var c: PrinterController
    @EnvironmentObject private var store: StoreManager
    @AppStorage("advancedUI") private var advanced = false
    @State private var showPurchase = false
    private var canPrint: Bool { store.isUnlocked || c.freePrintsLeft > 0 }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "printer")
            TextField("Printer name", text: $c.deviceName)
                .textFieldStyle(.roundedBorder).frame(width: 130)
            Button { Task { await c.refreshStatus() } } label: {
                Label("Status", systemImage: "arrow.clockwise")
            }.disabled(c.isBusy)
            if c.isBusy { ProgressView().controlSize(.small) }
            Text(c.message).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            if let s = c.status {
                HStack(spacing: 6) {
                    Circle().fill(TapeColor.color(s.tapeColor))
                        .overlay(Circle().stroke(.secondary.opacity(0.4))).frame(width: 14, height: 14)
                    Text("\(s.mediaWidthMM)mm")
                    Circle().fill(TapeColor.color(s.textColor)).frame(width: 8, height: 8)
                }.font(.callout)
            }
            Spacer()
            Toggle("Advanced", isOn: $advanced)
                .toggleStyle(.checkbox)
                .help("Show cell management and per-cell formatting controls")
            if !store.isUnlocked && c.freePrintsLeft > 0 {
                Button { showPurchase = true } label: {
                    Text("\(c.freePrintsLeft) free prints left").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Free trial — unlock unlimited printing")
            }
            Button {
                if canPrint { Task { await c.printCurrent() } } else { showPurchase = true }
            } label: {
                if canPrint {
                    Label(c.copies > 1 ? "Print \(c.copies)" : "Print", systemImage: "printer.fill")
                        .frame(minWidth: 80)
                } else {
                    Label("Purchase to Print", systemImage: "cart.fill").frame(minWidth: 80)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(c.isBusy || c.rendered == nil)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .sheet(isPresented: $showPurchase) { PurchaseView().environmentObject(store).environmentObject(c) }
        .alert("Wrong tape loaded", isPresented: Binding(get: { c.pendingMismatchPrint },
                                                         set: { c.pendingMismatchPrint = $0 })) {
            Button("Print Anyway") { Task { await c.printCurrent(force: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This label is designed for \(TapePreset.name(tape: c.designTape, text: c.designText)), "
                 + "but \(c.status.map { TapePreset.name(tape: $0.tapeColor, text: $0.textColor) } ?? "another tape") "
                 + "is loaded.")
        }
    }
}

// MARK: - Editor

struct EditorPanel: View {
    @EnvironmentObject private var c: PrinterController
    @AppStorage("advancedUI") private var advanced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { c.newLabel() } label: { Label("New", systemImage: "doc.badge.plus") }
                TapeMenu()
                Spacer()
                if advanced {
                    HStack(spacing: 8) {
                        Button { c.addCell(.text) } label: { Label("Aa", systemImage: "plus") }
                        Button { c.addCell(.symbol) } label: { Label("Symbol", systemImage: "plus") }
                        Button { c.addCell(.image) } label: { Label("Image", systemImage: "plus") }
                        Button { c.pasteImage() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                            .keyboardShortcut("v", modifiers: [.command, .shift])
                            .help("Paste an image from the clipboard as a new cell (⇧⌘V)")
                    }
                    Spacer()
                }
                Button { c.saveFavorite() } label: { Label("Save to Favorites", systemImage: "star") }
            }
            InteractivePreview()
            if advanced {
                HStack {
                    if let r = c.rendered {
                        Text(String(format: "%d cells · %d raster lines · ~%.1f cm · drag to reorder, drag off to delete",
                                    c.cells.count, r.lengthDots, Double(r.lengthDots) * 0.149 / 10))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.cells.count > 1 {
                        Stepper("Cell spacing: \(String(format: "%.1f", c.cellSpacingMM)) mm",
                                value: $c.cellSpacingMM, in: 0...20, step: 0.5)
                            .font(.caption).fixedSize()
                    }
                }
            }

            if let idx = c.selectedIndex {
                CellEditorView(cell: $c.cells[idx])
            } else {
                Text("Add a cell to begin.").foregroundStyle(.secondary)
            }

            PrintOptionsView()
        }
    }
}

// MARK: - Tape picker

/// A transparency-style checkerboard, used to represent clear tape.
struct Checkerboard: View {
    var square: CGFloat = 7
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.96)))
            let cols = Int(ceil(size.width / square)), rows = Int(ceil(size.height / square))
            for r in 0..<max(rows, 0) {
                for col in 0..<max(cols, 0) where (r + col) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * square, y: CGFloat(r) * square,
                                         width: square, height: square)),
                             with: .color(Color(white: 0.70)))
                }
            }
        }
    }
}

/// Background for a tape: a solid colour, or a checkerboard for clear tape.
struct TapeBackground: View {
    let code: UInt8
    var body: some View {
        ZStack {
            if TapeColor.isClear(code) { Checkerboard() } else { TapeColor.color(code) }
        }
    }
}

/// A bitmap swatch (tape background + an "A" in the text colour) for use as a
/// menu-item icon — macOS menus render an NSImage reliably but not a custom view.
func tapeSwatchImage(tape: UInt8, text: UInt8) -> NSImage {
    func ns(_ code: UInt8) -> NSColor {
        let c = TapeColor.rgb(code)
        return NSColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }
    let size = NSSize(width: 28, height: 16)
    let img = NSImage(size: size)
    img.lockFocus()
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
    NSGraphicsContext.saveGraphicsState(); path.addClip()
    if TapeColor.isClear(tape) {
        NSColor(white: 0.96, alpha: 1).setFill(); NSBezierPath(rect: rect).fill()
        NSColor(white: 0.70, alpha: 1).setFill()
        let sq: CGFloat = 4; var y: CGFloat = 0; var row = 0
        while y < size.height {
            var x: CGFloat = (row % 2 == 0) ? 0 : sq
            while x < size.width { NSBezierPath(rect: NSRect(x: x, y: y, width: sq, height: sq)).fill(); x += 2 * sq }
            y += sq; row += 1
        }
    } else {
        ns(tape).setFill(); NSBezierPath(rect: rect).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSColor.gray.withAlphaComponent(0.5).setStroke(); path.lineWidth = 1; path.stroke()
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: ns(text)]
    let s = NSAttributedString(string: "A", attributes: attrs); let ss = s.size()
    s.draw(at: NSPoint(x: (size.width - ss.width) / 2, y: (size.height - ss.height) / 2))
    img.unlockFocus()
    img.isTemplate = false
    return img
}

/// A small swatch showing a tape (background) and its text colour (an "A").
struct TapeSwatch: View {
    let tape: UInt8
    let text: UInt8
    var body: some View {
        TapeBackground(code: tape)
            .frame(width: 26, height: 15)
            .overlay(Text("A").font(.system(size: 10, weight: .bold)).foregroundStyle(TapeColor.color(text)))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.4)))
    }
}

/// Picks the tape this label is designed for (drives the tinted preview and the
/// print-time mismatch warning). The swatch sits *outside* the Menu because macOS
/// menu labels don't honour a custom view's frame.
struct TapeMenu: View {
    @EnvironmentObject private var c: PrinterController
    var body: some View {
        HStack(spacing: 6) {
            TapeSwatch(tape: c.designTape, text: c.designText)
            Menu {
                ForEach(TapePreset.all) { p in
                    let on = c.designTape == p.tape && c.designText == p.text
                    Button { c.setDesignTape(p) } label: {
                        Label {
                            Text(on ? "\(p.name)  ✓" : p.name)
                        } icon: {
                            Image(nsImage: tapeSwatchImage(tape: p.tape, text: p.text)).renderingMode(.original)
                        }
                    }
                }
            } label: {
                Text(TapePreset.name(tape: c.designTape, text: c.designText)).lineLimit(1).font(.callout)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .help("Tape this label is designed for")
    }
}

struct InteractivePreview: View {
    @EnvironmentObject private var c: PrinterController
    private let tapeH: CGFloat = 84
    private let printFraction: CGFloat = 0.745
    private let marginDots: CGFloat = 18
    @State private var dragID: LabelCell.ID?
    @State private var dragDX: CGFloat = 0
    @State private var dragDY: CGFloat = 0

    private struct CellRender: Identifiable {
        let id: LabelCell.ID
        let image: CGImage?
        let dots: Int
        let width: CGFloat
    }

    var body: some View {
        let imgH = tapeH * printFraction
        let scale = imgH / 64
        let items: [CellRender] = c.cells.map { cell in
            let cg = c.cellImage(cell)
            let dots = cg?.width ?? 1
            // A cell that fails to render (e.g. an old image cell whose file the
            // sandbox can't read) would be ~1px wide and impossible to select or
            // delete — give it a visible placeholder width.
            let width = cg == nil ? max(CGFloat(dots) * scale, 26) : CGFloat(dots) * scale
            // Show the cell in the design tape's colours (ink = text, bg = tape).
            return CellRender(id: cell.id, image: cg.flatMap { c.tintedDesign($0) } ?? cg, dots: dots, width: width)
        }
        let gap = CGFloat(c.cellSpacingDots) * scale
        let margin = marginDots * scale
        let totalW = margin * 2 + items.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, items.count - 1))

        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(spacing: 3) {
                    if items.count > 1 { ruler(items, gap: gap, margin: margin, totalW: totalW) }
                    ZStack(alignment: .leading) {
                        TapeBackground(code: c.designTape)
                        HStack(spacing: 0) {
                            Color.clear.frame(width: margin)
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                if idx > 0 { Color.clear.frame(width: gap) }
                                cellView(item, imgH: imgH, items: items, gap: gap)
                            }
                            Color.clear.frame(width: margin)
                        }
                    }
                    .frame(width: totalW, height: tapeH)
                    .overlay(alignment: .trailing) { Rectangle().fill(.red.opacity(0.7)).frame(width: 1) }
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.secondary.opacity(0.35)))
                }
                VStack(spacing: 1) { Image(systemName: "scissors").font(.caption2); Text("end").font(.system(size: 8)) }
                    .foregroundStyle(.red.opacity(0.8)).padding(.leading, 3).padding(.bottom, 6)
                if c.copies > 1 {
                    Text("× \(c.copies)").font(.title3).bold().foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 10)
                }
            }.padding(10)
        }
        .frame(height: tapeH + (c.cells.count > 1 ? 48 : 28)).frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        // Right-click empty space in the preview to paste a clipboard image as a
        // new cell (per-cell menus take precedence when right-clicking a cell).
        .contextMenu {
            Button { c.pasteImage() } label: { Label("Paste Image", systemImage: "doc.on.clipboard") }
        }
    }

    private func cellView(_ item: CellRender, imgH: CGFloat, items: [CellRender], gap: CGFloat) -> some View {
        let isDragging = dragID == item.id
        return Group {
            if let cg = item.image {
                Image(decorative: cg, scale: 1).resizable().interpolation(.none).frame(width: item.width, height: imgH)
            } else {
                Color.gray.opacity(0.2).frame(width: item.width, height: imgH)
            }
        }
        .opacity(isDragging ? 0.65 : 1)
        .offset(x: isDragging ? dragDX : 0, y: isDragging ? dragDY : 0)
        .zIndex(isDragging ? 1 : 0)
        .onTapGesture { c.selectedID = item.id }
        .contextMenu {
            Button { c.copyCell(item.id) } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button(role: .destructive) { c.delete(id: item.id) } label: { Label("Delete Cell", systemImage: "trash") }
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { v in
                    if dragID == nil { dragID = item.id; c.selectedID = item.id }
                    guard dragID == item.id, let i = c.cells.firstIndex(where: { $0.id == item.id }) else { return }
                    dragDX = v.translation.width; dragDY = v.translation.height
                    if i < c.cells.count - 1 {
                        let nW = width(of: c.cells[i + 1].id, items) + gap
                        if dragDX > nW / 2 { c.cells.swapAt(i, i + 1); dragDX -= nW }
                    }
                    if i > 0 {
                        let nW = width(of: c.cells[i - 1].id, items) + gap
                        if dragDX < -nW / 2 { c.cells.swapAt(i, i - 1); dragDX += nW }
                    }
                }
                .onEnded { v in
                    if abs(v.translation.height) > 55 { c.delete(id: item.id) }
                    dragID = nil; dragDX = 0; dragDY = 0
                }
        )
    }

    private func width(of id: LabelCell.ID, _ items: [CellRender]) -> CGFloat {
        items.first { $0.id == id }?.width ?? 1
    }

    private func ruler(_ items: [CellRender], gap: CGFloat, margin: CGFloat, totalW: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: margin)
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 { Color.clear.frame(width: gap) }
                let sel = item.id == c.selectedID
                VStack(spacing: 1) {
                    Text("Cell \(idx + 1)")
                        .font(.system(size: 9, weight: sel ? .bold : .regular))
                        .foregroundStyle(sel ? Color.accentColor : Color.primary).lineLimit(1)
                    Text(String(format: "%.0f mm", Double(item.dots) * 0.149))
                        .font(.system(size: 8))
                        .foregroundStyle(sel ? Color.accentColor.opacity(0.85) : .secondary)
                    HStack(spacing: 0) {
                        Rectangle().frame(width: 1, height: sel ? 6 : 4)
                        Rectangle().frame(height: sel ? 2 : 1)
                        Rectangle().frame(width: 1, height: sel ? 6 : 4)
                    }.foregroundStyle(sel ? Color.accentColor : .secondary.opacity(0.45))
                }
                .frame(width: max(item.width, 1)).clipped()
                .contentShape(Rectangle())
                .onTapGesture { c.selectedID = item.id }
            }
            Color.clear.frame(width: margin)
        }.frame(width: totalW)
    }
}

// MARK: - Print options

struct PrintOptionsView: View {
    @EnvironmentObject private var c: PrinterController
    var body: some View {
        GroupBox {
            DisclosureGroup("Print Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Stepper("Copies: \(c.copies)", value: $c.copies, in: 1...999).frame(maxWidth: 180)
                        Stepper("Start: \(c.startIndex)", value: $c.startIndex, in: 1...99999).frame(maxWidth: 170)
                        Stepper(c.totalCount == 0 ? "Total: auto (\(c.effectiveCount))" : "Total: \(c.totalCount)",
                                value: $c.totalCount, in: 0...99999).frame(maxWidth: 210)
                    }
                    HStack {
                        Stepper("Label spacing: \(String(format: "%.1f", c.spacingMM)) mm",
                                value: $c.spacingMM, in: 0...30, step: 0.5).frame(maxWidth: 230)
                        Toggle("Cut line between labels", isOn: $c.cutLine)
                    }
                    Text("Text tokens: /i index · /c count · /n name · /p phone · /s street · /e email · /d date. Saved labels keep the tokens; the preview shows the expansions.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Date formats: /d Jun 14, 2026 · /d1 6/14/26 · /d2 06/14/2026 · /d3 2026-06-14 · /d4 14 Jun 2026 · /d5 June 14, 2026. A token only applies when followed by a space, punctuation, or line end.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Enter your name, phone, street, and email in Settings (gear icon) — those values fill the /n /p /s /e tokens.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 6)
            }.padding(6)
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var c: PrinterController
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPurchase = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contact").font(.headline)
            Form {
                TextField("Name", text: $c.contactName)
                TextField("Phone", text: $c.contactPhone)
                TextField("Street", text: $c.contactStreet)
                TextField("Email", text: $c.contactEmail)
            }
            Text("Used by the /n /p /s /e text tokens. /d inserts today's date. These are saved between launches.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Divider()
            Text("License").font(.headline)
            if store.isUnlocked {
                Label("Full version — purchased", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                HStack {
                    Text("Free trial — \(c.freePrintsLeft) of \(PrinterController.freePrintLimit) prints left")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Unlock…") { showPurchase = true }
                }
                Button("Restore Purchase") { Task { await store.restore() } }.buttonStyle(.link)
            }

            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 380)
        .sheet(isPresented: $showPurchase) { PurchaseView().environmentObject(store).environmentObject(c) }
        .onDisappear { c.flushContact() }
    }
}

// MARK: - Cell editor

struct CellEditorView: View {
    @EnvironmentObject private var c: PrinterController
    @AppStorage("advancedUI") private var advanced = false
    @Binding var cell: LabelCell

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if advanced {
                HStack(spacing: 14) {
                    Picker("Type", selection: $cell.kind) {
                        Text("Text").tag(LabelCell.Kind.text)
                        Text("Image").tag(LabelCell.Kind.image)
                        Text("Symbol").tag(LabelCell.Kind.symbol)
                    }.frame(width: 140)
                    HStack(spacing: 6) {
                        Text("Style").fixedSize()
                        Picker("Style", selection: $cell.style) {
                            Text("Normal").tag(CellStyle.normal)
                            Text("Inverted").tag(CellStyle.inverted)
                        }.labelsHidden().pickerStyle(.segmented).fixedSize()
                    }
                    if cell.kind == .text {
                        Picker("Font", selection: $cell.fontName) {
                            ForEach(fontChoices, id: \.self) { Text($0).tag($0) }
                        }.frame(width: 165)
                        Picker("Size", selection: $cell.sizing) {
                            Text("Fit text").tag(SizingMode.fitText)
                            Text("Consistent").tag(SizingMode.capHeight)
                        }.frame(width: 150)
                    }
                    Spacer()
                    Button(role: .destructive) { c.delete(id: cell.id) } label: {
                        Label("Delete Cell", systemImage: "trash")
                    }
                    .disabled(c.cells.count <= 1)
                    .help("Remove this cell from the label")
                }
                }
                switch cell.kind {
                case .text: textControls
                case .image: imageControls
                case .symbol: SymbolPicker(selection: $cell.symbolName)
                }
            }.padding(6)
        }
        .onChange(of: cell.kind) { _, k in
            if k == .symbol, cell.symbolName == nil { cell.symbolName = SymbolCatalog.defaultName }
            if k == .text, cell.text.isEmpty { cell.text = "Text" }
        }
    }

    private var textControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabelTextEditor(text: $cell.text, focusToken: c.focusTextToken).frame(height: 60)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
            Text("Return adds a line. Tokens like /i /c /n /d are allowed (see Print Settings).")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var imageControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { c.pickImage(for: cell.id) } label: { Label("Choose Image…", systemImage: "photo") }
                if let p = cell.imagePath {
                    Text((p as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                } else if cell.imageData != nil {
                    Text("Embedded image").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("PNG, JPEG, SVG, or single-page PDF.").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            DisclosureGroup("Adjust Image") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Dither (for photos)", isOn: $cell.dithered)
                        .toggleStyle(.checkbox)
                        .help("Floyd–Steinberg dithering — good for photos; leave off for line art, logos, and text.")
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Text("Brightness").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $cell.brightness, in: -1...1).frame(width: 130)
                        }
                        HStack(spacing: 6) {
                            Text("Contrast").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $cell.contrast, in: -1...1).frame(width: 130)
                        }
                        Button("Reset") { cell.brightness = 0; cell.contrast = 0 }
                            .font(.caption).disabled(cell.brightness == 0 && cell.contrast == 0)
                    }
                    Text("Tune the black/white cutoff for logos & line art (or use Dither for photos).")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 6)
            }
        }
    }
}

/// A multi-line text editor (NSTextView-backed) that, unlike SwiftUI's TextEditor,
/// can take focus and select all its text on demand (see `focusToken`).
struct LabelTextEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 14)
        tv.string = text
        tv.drawsBackground = false
        // Label text is literal — disable macOS substitutions that rewrite input.
        // automaticTextReplacement covers double-space → ". " (the period the user
        // keeps deleting); the rest stop smart quotes/dashes and autocorrect.
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        scroll.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        context.coordinator.lastFocusToken = focusToken   // don't focus on first build
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        // Keep the coordinator's binding current: SwiftUI recreates this struct on
        // every update (e.g. when cells reorder and the bound index changes), but
        // the coordinator persists. Without this, textDidChange writes through a
        // stale binding (to the wrong cell) and edits silently vanish.
        context.coordinator.parent = self
        if tv.string != text { tv.string = text }
        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                guard let window = tv.window else { return }
                window.makeFirstResponder(tv)
                tv.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LabelTextEditor
        var lastFocusToken = 0
        init(_ parent: LabelTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
        // Hard-block the macOS double-space → ". " substitution (the property flag
        // doesn't reliably disable it): if a single existing space is about to be
        // replaced with a "."-leading string, keep the two spaces instead.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard replacementString == ". ",
                  affectedCharRange.length == 1,
                  affectedCharRange.location < (textView.string as NSString).length,
                  (textView.string as NSString).substring(with: affectedCharRange) == " "
            else { return true }
            textView.insertText("  ", replacementRange: affectedCharRange)
            return false
        }
    }
}

struct SymbolPicker: View {
    @Binding var selection: String?
    @State private var search = ""
    private let cols = [GridItem(.adaptive(minimum: 40), spacing: 8)]

    var body: some View {
        let names = BootstrapIcons.search(search)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Symbol").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("Filter icons…", text: $search)
                    .textFieldStyle(.roundedBorder).frame(width: 170)
                Text("\(names.count)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            ScrollView {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        IconCell(name: name, selected: selection == name)
                            .onTapGesture { selection = name }
                    }
                }.padding(2)
            }.frame(height: 150)
        }
    }
}

private struct IconCell: View {
    let name: String
    let selected: Bool
    var body: some View {
        Group {
            if let cg = BootstrapIcons.image(named: name) {
                Image(decorative: cg, scale: 1).resizable().interpolation(.high)
                    .scaledToFit().padding(6)
            } else {
                Color.clear
            }
        }
        .frame(width: 40, height: 36)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(selected ? Color.accentColor : .secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
        .help(name)
    }
}

// MARK: - Favorites

private enum FavRow: Identifiable {
    case folder(FavoriteFolder)
    case item(SavedLabelModel)
    var id: String {
        switch self {
        case .folder(let f): return "f-\(f.id.uuidString)"
        case .item(let i): return "i-\(i.id.uuidString)"
        }
    }
}

struct FavoritesSidebar: View {
    @EnvironmentObject private var c: PrinterController
    @State private var tab = 0   // 0 = Favorites, 1 = History
    @State private var renamingFolder: FavoriteFolder?
    @State private var renameText = ""
    @Query(filter: #Predicate<SavedLabelModel> { $0.kind == "favorite" },
           sort: \SavedLabelModel.createdAt, order: .reverse) private var favorites: [SavedLabelModel]
    @Query(filter: #Predicate<SavedLabelModel> { $0.kind == "history" },
           sort: \SavedLabelModel.createdAt, order: .reverse) private var history: [SavedLabelModel]
    @Query(sort: \FavoriteFolder.createdAt) private var folders: [FavoriteFolder]

    /// Flattened display order: ungrouped favorites first, then each top-level
    /// folder followed (when expanded) by its subfolders and favorites. No
    /// indentation — hierarchy is conveyed by collapse/expand.
    private func favRows() -> [FavRow] {
        func items(_ folderID: UUID?) -> [SavedLabelModel] {
            favorites.filter { $0.folderID == folderID }
                .sorted { ($0.sortIndex, -$0.createdAt.timeIntervalSince1970) < ($1.sortIndex, -$1.createdAt.timeIntervalSince1970) }
        }
        func subs(_ parentID: UUID?) -> [FavoriteFolder] {
            folders.filter { $0.parentID == parentID }
                .sorted { ($0.sortIndex, $0.createdAt.timeIntervalSince1970) < ($1.sortIndex, $1.createdAt.timeIntervalSince1970) }
        }
        var rows: [FavRow] = []
        for fav in items(nil) { rows.append(.item(fav)) }
        func add(_ folder: FavoriteFolder) {
            rows.append(.folder(folder))
            guard folder.expanded else { return }
            for child in subs(folder.id) { add(child) }
            for fav in items(folder.id) { rows.append(.item(fav)) }
        }
        for f in subs(nil) { add(f) }
        return rows
    }

    // MARK: Drag & drop helpers

    private func favorite(_ id: String) -> SavedLabelModel? {
        guard id.hasPrefix("i-"), let u = UUID(uuidString: String(id.dropFirst(2))) else { return nil }
        return favorites.first { $0.id == u }
    }
    private func folderBy(_ id: String) -> FavoriteFolder? {
        guard id.hasPrefix("f-"), let u = UUID(uuidString: String(id.dropFirst(2))) else { return nil }
        return folders.first { $0.id == u }
    }
    private func receiveDrop(_ providers: [NSItemProvider], _ action: @escaping (String) -> Void) -> Bool {
        guard let p = providers.first else { return false }
        p.loadObject(ofClass: NSString.self) { obj, _ in
            if let s = obj as? String { DispatchQueue.main.async { action(s) } }
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Favorites").tag(0)
                Text("History").tag(1)
            }.pickerStyle(.segmented).labelsHidden().padding(8)
            Divider()
            ScrollViewReader { proxy in
                List {
                    if tab == 0 {
                        let rows = favRows()
                        if rows.isEmpty { Text("No favorites yet").foregroundStyle(.secondary) }
                        ForEach(rows) { row in
                            switch row {
                            case .folder(let f):
                                folderHeader(f).id(row.id)
                                    .onDrag { NSItemProvider(object: "f-\(f.id.uuidString)" as NSString) }
                                    .onDrop(of: [.text], isTargeted: nil) { providers in
                                        receiveDrop(providers) { s in
                                            if let it = favorite(s) { c.moveFavorite(it, toFolder: f.id) }
                                            else if let dragged = folderBy(s) { c.nestFolder(dragged, under: f.id) }
                                        }
                                    }
                            case .item(let item):
                                itemRow(item).id(row.id)
                                    .onDrag { NSItemProvider(object: "i-\(item.id.uuidString)" as NSString) }
                                    .onDrop(of: [.text], isTargeted: nil) { providers in
                                        receiveDrop(providers) { s in
                                            if let dragged = favorite(s), dragged.id != item.id {
                                                c.reorderFavorite(dragged, before: item)
                                            }
                                        }
                                    }
                            }
                        }
                        // Empty space below the list: right-click to add a folder, or
                        // drop here to move a label/folder to the top level.
                        Color.clear.frame(height: 80).listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button { promptRename(c.addFolder()) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                            }
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                receiveDrop(providers) { s in
                                    if let it = favorite(s) { c.moveFavorite(it, toFolder: nil) }
                                    else if let dragged = folderBy(s) { c.nestFolder(dragged, under: nil) }
                                }
                            }
                    } else {
                        if history.isEmpty { Text("No history yet").foregroundStyle(.secondary) }
                        ForEach(history) { item in itemRow(item).id("i-\(item.id.uuidString)") }
                    }
                }
                // A newly saved/printed label is inserted at the top; snap it into view.
                .onChange(of: tab == 0 ? favorites.first?.id : history.first?.id) { _, newID in
                    if let id = newID { proxy.scrollTo("i-\(id.uuidString)", anchor: .top) }
                }
            }
        }
        .frame(minWidth: 180)
        .alert("Rename Folder", isPresented: Binding(get: { renamingFolder != nil },
                                                     set: { if !$0 { renamingFolder = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let f = renamingFolder { c.renameFolder(f, renameText) }; renamingFolder = nil }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
    }

    private func promptRename(_ folder: FavoriteFolder?) {
        guard let folder else { return }
        renameText = folder.name; renamingFolder = folder
    }

    // MARK: Folder header

    @ViewBuilder private func folderHeader(_ f: FavoriteFolder) -> some View {
        let color = FolderPalette.color(f.colorIndex)
        HStack(spacing: 6) {
            Image(systemName: f.expanded ? "chevron.down" : "chevron.right")
                .font(.caption2).foregroundStyle(.secondary).frame(width: 9)
            Image(systemName: "folder.fill").foregroundStyle(color).font(.callout)
            Text(f.name.isEmpty ? "Folder" : f.name).font(.callout.weight(.medium)).lineLimit(1)
            Spacer(minLength: 2)
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(color.opacity(0.20), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { c.toggleFolder(f) }
        .contextMenu {
            Button { promptRename(c.addFolder()) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
            Button { promptRename(c.addFolder(parentID: f.id)) } label: { Label("New Subfolder", systemImage: "folder.fill.badge.plus") }
            Button { promptRename(f) } label: { Label("Rename…", systemImage: "pencil") }
            Menu("Color") {
                ForEach(FolderPalette.colors.indices, id: \.self) { i in
                    Button { c.setFolderColor(f, i) } label: {
                        Label("Color \(i + 1)", systemImage: f.colorIndex == i ? "checkmark" : "circle")
                    }
                }
            }
            Button(role: .destructive) { c.deleteFolder(f) } label: { Label("Delete Folder", systemImage: "trash") }
        }
    }

    // MARK: Item row (favorite or history)

    @ViewBuilder private func itemRow(_ item: SavedLabelModel) -> some View {
        Group {
            if let raw = c.previewImage(item.cells, spacingMM: item.cellSpacingMM) {
                let tape = UInt8(clamping: item.tapeColor), text = UInt8(clamping: item.textColor)
                let cg = c.tinted(raw, tape: tape, text: text) ?? raw
                Image(decorative: cg, scale: 1).resizable().interpolation(.none)
                    .aspectRatio(CGFloat(cg.width) / CGFloat(cg.height), contentMode: .fit)
                    .frame(height: 34).padding(.horizontal, 3).background(TapeBackground(code: tape))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(maxWidth: 168, alignment: .leading).clipped()
            } else {
                Text(item.name.isEmpty ? "Label" : item.name).font(.caption)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { c.load(item) }
        .contextMenu {
            Button { c.load(item) } label: { Label("Load", systemImage: "tray.and.arrow.down") }
            if item.isFavorite {
                Menu("Move to Folder") {
                    Button { c.moveFavorite(item, toFolder: nil) } label: {
                        Label("Top Level", systemImage: item.folderID == nil ? "checkmark" : "tray")
                    }
                    if !folders.isEmpty { Divider() }
                    ForEach(folders) { f in
                        Button { c.moveFavorite(item, toFolder: f.id) } label: {
                            Label(f.name.isEmpty ? "Folder" : f.name, systemImage: item.folderID == f.id ? "checkmark" : "folder")
                        }
                    }
                }
                Button { promptRename(c.addFolder()) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
            } else {
                Button { c.saveFavorite(from: item) } label: { Label("Save to Favorites", systemImage: "star") }
            }
            Button(role: .destructive) { c.delete(item) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
