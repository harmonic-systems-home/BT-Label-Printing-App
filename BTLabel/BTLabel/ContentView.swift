import SwiftUI
import SwiftData
import PTouchKit

private let fontChoices = [
    "Helvetica", "Helvetica Neue", "Arial", "Avenir Next", "Gill Sans",
    "Georgia", "Times New Roman", "Menlo", "Courier New", "Marker Felt",
]

struct ContentView: View {
    @EnvironmentObject private var c: PrinterController
    @Environment(\.modelContext) private var modelContext
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            FavoritesSidebar().navigationTitle("Favorites")
        } detail: {
            VStack(spacing: 0) {
                PrinterStatusBar()
                Divider()
                ScrollView { EditorPanel().padding() }
            }
            .navigationTitle("BTLabel")
            .toolbar {
                ToolbarItem { Button { showSettings = true } label: { Image(systemName: "gearshape") } }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(c) }
        .onAppear { c.modelContext = modelContext }
    }
}

// MARK: - Status bar

struct PrinterStatusBar: View {
    @EnvironmentObject private var c: PrinterController
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
            Button { Task { await c.printCurrent() } } label: {
                Label(c.copies > 1 ? "Print \(c.copies)" : "Print", systemImage: "printer.fill")
                    .frame(minWidth: 80)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(c.isBusy || c.rendered == nil)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}

// MARK: - Editor

struct EditorPanel: View {
    @EnvironmentObject private var c: PrinterController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { c.newLabel() } label: { Label("New", systemImage: "doc.badge.plus") }
                Spacer()
                HStack(spacing: 8) {
                    Button { c.addCell(.text) } label: { Label("Aa", systemImage: "plus") }
                    Button { c.addCell(.image) } label: { Label("Image", systemImage: "plus") }
                    Button { c.addCell(.symbol) } label: { Label("Symbol", systemImage: "plus") }
                }
                Spacer()
                Button { c.saveFavorite() } label: { Label("Save to Favorites", systemImage: "star") }
            }
            InteractivePreview()
            if let r = c.rendered {
                Text(String(format: "%d cells · %d raster lines · ~%.1f cm · drag to reorder, drag off to delete",
                            c.cells.count, r.lengthDots, Double(r.lengthDots) * 0.149 / 10))
                    .font(.caption).foregroundStyle(.secondary)
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

struct InteractivePreview: View {
    @EnvironmentObject private var c: PrinterController
    private let tapeH: CGFloat = 84
    private let printFraction: CGFloat = 0.745
    private let marginDots: CGFloat = 18
    private let gapDots: CGFloat = 18
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
        let tape = c.status.map { TapeColor.color($0.tapeColor) } ?? .white
        let imgH = tapeH * printFraction
        let scale = imgH / 64
        let items: [CellRender] = c.cells.map { cell in
            let cg = c.cellImage(cell)
            let dots = cg?.width ?? 1
            return CellRender(id: cell.id, image: cg, dots: dots, width: CGFloat(dots) * scale)
        }
        let gap = gapDots * scale
        let margin = marginDots * scale
        let totalW = margin * 2 + items.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, items.count - 1))

        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(spacing: 3) {
                    if items.count > 1 { ruler(items, gap: gap, margin: margin, totalW: totalW) }
                    ZStack(alignment: .leading) {
                        Rectangle().fill(tape)
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
    }

    private func cellView(_ item: CellRender, imgH: CGFloat, items: [CellRender], gap: CGFloat) -> some View {
        let isDragging = dragID == item.id
        let selected = c.selectedID == item.id
        return Group {
            if let cg = item.image {
                Image(decorative: cg, scale: 1).resizable().interpolation(.none).frame(width: item.width, height: imgH)
            } else {
                Color.gray.opacity(0.2).frame(width: item.width, height: imgH)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .opacity(isDragging ? 0.65 : 1)
        .offset(x: isDragging ? dragDX : 0, y: isDragging ? dragDY : 0)
        .zIndex(isDragging ? 1 : 0)
        .onTapGesture { c.selectedID = item.id }
        .contextMenu {
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
                VStack(spacing: 0) {
                    Text("Cell \(idx + 1)").font(.system(size: 9)).lineLimit(1)
                    Text(String(format: "%.0f mm", Double(item.dots) * 0.149)).font(.system(size: 8)).foregroundStyle(.secondary)
                }
                .frame(width: max(item.width, 1)).clipped()
                .overlay(alignment: .bottom) {
                    HStack(spacing: 0) {
                        Rectangle().frame(width: 1, height: 4)
                        Rectangle().frame(height: 1)
                        Rectangle().frame(width: 1, height: 4)
                    }.foregroundStyle(.secondary.opacity(0.45))
                }
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
                        Stepper("Spacing: \(String(format: "%.1f", c.spacingMM)) mm",
                                value: $c.spacingMM, in: 0...30, step: 0.5).frame(maxWidth: 220)
                        Toggle("Cut line between labels", isOn: $c.cutLine)
                    }
                    Text("Text tokens: /i index · /c count · /n name · /p phone · /s street · /e email · /d date. Saved labels keep the tokens; the preview shows the expansions.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 6)
            }.padding(6)
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var c: PrinterController
    @Environment(\.dismiss) private var dismiss
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
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 380)
    }
}

// MARK: - Cell editor

struct CellEditorView: View {
    @EnvironmentObject private var c: PrinterController
    @Binding var cell: LabelCell

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
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
                }
                switch cell.kind {
                case .text: textControls
                case .image: imageControls
                case .symbol: SymbolPicker(selection: $cell.symbolName)
                }
            }.padding(6)
        }
        .onChange(of: cell.kind) { _, k in
            if k == .symbol, cell.symbolName == nil { cell.symbolName = SymbolCatalog.names.first }
            if k == .text, cell.text.isEmpty { cell.text = "Text" }
        }
    }

    private var textControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $cell.text).font(.system(size: 14)).frame(height: 60)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
            Text("Return adds a line. Tokens like /i /c /n /d are allowed (see Print options).")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var imageControls: some View {
        HStack(spacing: 12) {
            Button { c.pickImage(for: cell.id) } label: { Label("Choose Image…", systemImage: "photo") }
            if let p = cell.imagePath {
                Text((p as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            } else {
                Text("PNG, JPEG, or single-page PDF.").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct SymbolPicker: View {
    @Binding var selection: String?
    private let cols = [GridItem(.adaptive(minimum: 38), spacing: 8)]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Symbol").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(SymbolCatalog.names, id: \.self) { name in
                        Image(systemName: name).font(.title2).frame(width: 38, height: 34)
                            .background(selection == name ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture { selection = name }
                    }
                }.padding(2)
            }.frame(height: 130)
        }
    }
}

// MARK: - Favorites

struct FavoritesSidebar: View {
    @EnvironmentObject private var c: PrinterController
    @Query(sort: \SavedLabelModel.createdAt, order: .reverse) private var favorites: [SavedLabelModel]

    var body: some View {
        List {
            if favorites.isEmpty { Text("No favorites yet").foregroundStyle(.secondary) }
            ForEach(favorites) { fav in
                Group {
                    if let cg = c.previewImage(fav.cells) {
                        Image(decorative: cg, scale: 1).resizable().interpolation(.none)
                            .aspectRatio(CGFloat(cg.width) / CGFloat(cg.height), contentMode: .fit)
                            .frame(height: 34).padding(.horizontal, 3).background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .frame(maxWidth: 168, alignment: .leading).clipped()
                    } else {
                        Text(fav.name.isEmpty ? "Label" : fav.name).font(.caption)
                    }
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture { c.load(fav) }
                .contextMenu {
                    Button { c.load(fav) } label: { Label("Load", systemImage: "tray.and.arrow.down") }
                    Button(role: .destructive) { c.delete(fav) } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .onDelete { idxs in idxs.forEach { c.delete(favorites[$0]) } }
        }.frame(minWidth: 180)
    }
}
