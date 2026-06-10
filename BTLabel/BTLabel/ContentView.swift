import SwiftUI
import PTouchKit

private let fontChoices = [
    "Helvetica", "Helvetica Neue", "Arial", "Avenir Next", "Gill Sans",
    "Georgia", "Times New Roman", "Menlo", "Courier New", "Marker Felt",
]

struct ContentView: View {
    @EnvironmentObject private var c: PrinterController
    @State private var favSelection: SavedLabel.ID?

    var body: some View {
        NavigationSplitView {
            FavoritesSidebar(selection: $favSelection).navigationTitle("Favorites")
        } detail: {
            VStack(spacing: 0) {
                PrinterStatusBar()
                Divider()
                ScrollView { EditorPanel().padding() }
            }
            .navigationTitle("BTLabel")
        }
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
            if let s = c.status {
                HStack(spacing: 6) {
                    Circle().fill(TapeColor.color(s.tapeColor))
                        .overlay(Circle().stroke(.secondary.opacity(0.4))).frame(width: 14, height: 14)
                    Text("\(s.mediaWidthMM)mm")
                    Circle().fill(TapeColor.color(s.textColor)).frame(width: 8, height: 8)
                }.font(.callout)
            }
            Spacer()
            if c.isBusy { ProgressView().controlSize(.small) }
            Text(c.message).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}

// MARK: - Editor

struct EditorPanel: View {
    @EnvironmentObject private var c: PrinterController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview").font(.headline)
            PreviewCard()
            if let r = c.rendered {
                Text(String(format: "%d cells · %d raster lines · ~%.1f cm",
                            c.cells.count, r.lengthDots, Double(r.lengthDots) * 0.149 / 10))
                    .font(.caption).foregroundStyle(.secondary)
            }

            CellStrip()

            if let idx = c.selectedIndex {
                CellEditorView(cell: $c.cells[idx])
            } else {
                Text("Add a cell to begin.").foregroundStyle(.secondary)
            }

            HStack {
                Button { c.saveFavorite() } label: { Label("Save to Favorites", systemImage: "star") }
                Spacer()
                Button { Task { await c.printCurrent() } } label: {
                    Label("Print", systemImage: "printer.fill").frame(minWidth: 90)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(c.isBusy || c.rendered == nil)
            }
        }
    }
}

struct PreviewCard: View {
    @EnvironmentObject private var c: PrinterController
    private let stripH: CGFloat = 72

    var body: some View {
        let tape = c.status.map { TapeColor.color($0.tapeColor) } ?? .white
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .center, spacing: 0) {
                if let cg = c.rendered?.preview {
                    let w = stripH * CGFloat(cg.width) / CGFloat(cg.height)
                    Image(decorative: cg, scale: 1)
                        .resizable().interpolation(.none)
                        .frame(width: w, height: stripH)
                        .background(tape)
                        .overlay(alignment: .trailing) {            // where printing stops
                            Rectangle().fill(.red.opacity(0.7)).frame(width: 1)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.secondary.opacity(0.35)))
                    VStack(spacing: 1) {                            // cut / end marker
                        Image(systemName: "scissors").font(.caption2)
                        Text("end").font(.system(size: 8))
                    }
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.leading, 3)
                } else {
                    Text("Empty label").foregroundStyle(.secondary).frame(height: stripH)
                }
            }
            .padding(10)
        }
        .frame(height: 100).frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
    }
}

// MARK: - Cell strip

struct CellStrip: View {
    @EnvironmentObject private var c: PrinterController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    Button("Text") { c.addCell(.text) }
                    Button("Image…") { c.addCell(.image) }
                    Button("Symbol") { c.addCell(.symbol) }
                } label: { Label("Add Cell", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()

                Divider().frame(height: 18)
                Button { c.move(-1) } label: { Image(systemName: "arrow.left") }
                    .disabled(c.selectedIndex == nil)
                Button { c.move(1) } label: { Image(systemName: "arrow.right") }
                    .disabled(c.selectedIndex == nil)
                Button(role: .destructive) { c.deleteSelected() } label: { Image(systemName: "trash") }
                    .disabled(c.selectedIndex == nil || c.cells.count <= 1)
                Spacer()
            }
            .buttonStyle(.bordered)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(c.cells) { cell in
                        CellChip(cell: cell, selected: cell.id == c.selectedID)
                            .onTapGesture { c.selectedID = cell.id }
                    }
                }.padding(.vertical, 2)
            }
        }
    }
}

struct CellChip: View {
    let cell: LabelCell
    let selected: Bool
    var body: some View {
        let inverted = cell.style == .inverted
        HStack(spacing: 6) {
            switch cell.kind {
            case .text: Image(systemName: "textformat"); Text(cell.text.isEmpty ? "Text" : cell.text).lineLimit(1)
            case .image: Image(systemName: "photo"); Text((cell.imagePath as NSString?)?.lastPathComponent ?? "Image").lineLimit(1)
            case .symbol: Image(systemName: cell.symbolName ?? "questionmark"); Text("Symbol")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: 160)
        .background(inverted ? Color.black : Color.gray.opacity(0.12))
        .foregroundStyle(inverted ? Color.white : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
    }
}

// MARK: - Cell editor

struct CellEditorView: View {
    @EnvironmentObject private var c: PrinterController
    @Binding var cell: LabelCell

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Type", selection: $cell.kind) {
                        Text("Text").tag(LabelCell.Kind.text)
                        Text("Image").tag(LabelCell.Kind.image)
                        Text("Symbol").tag(LabelCell.Kind.symbol)
                    }.frame(maxWidth: 200)
                    Picker("Style", selection: $cell.style) {
                        Text("Normal").tag(CellStyle.normal)
                        Text("Inverted").tag(CellStyle.inverted)
                    }.pickerStyle(.segmented).frame(maxWidth: 200)
                    Spacer()
                }
                switch cell.kind {
                case .text: textControls
                case .image: imageControls
                case .symbol: SymbolPicker(selection: $cell.symbolName)
                }
            }
            .padding(6)
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
            Text("Return adds a second line — the font shrinks to fit.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Picker("Font", selection: $cell.fontName) {
                    ForEach(fontChoices, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 220)
                Picker("Size", selection: $cell.sizing) {
                    Text("Fit text").tag(SizingMode.fitText)
                    Text("Consistent").tag(SizingMode.capHeight)
                }.frame(maxWidth: 190)
            }
        }
    }

    private var imageControls: some View {
        HStack(spacing: 12) {
            Button { c.pickImage(for: cell.id) } label: { Label("Choose Image…", systemImage: "photo") }
            if let p = cell.imagePath {
                Text((p as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
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
                        Image(systemName: name)
                            .font(.title2).frame(width: 38, height: 34)
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
    @Binding var selection: SavedLabel.ID?
    var body: some View {
        List(selection: $selection) {
            if c.favorites.isEmpty { Text("No favorites yet").foregroundStyle(.secondary) }
            ForEach(c.favorites) { fav in
                Text(fav.name).lineLimit(1).tag(fav.id)
                    .contentShape(Rectangle()).onTapGesture { c.load(fav) }
            }
            .onDelete { idx in c.favorites.remove(atOffsets: idx) }
        }.frame(minWidth: 180)
    }
}
