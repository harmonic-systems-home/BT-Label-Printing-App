import SwiftUI
import PTouchKit

private let fontChoices = [
    "Helvetica", "Helvetica Neue", "Arial", "Avenir Next", "Gill Sans",
    "Georgia", "Times New Roman", "Menlo", "Courier New", "Marker Felt",
]

struct ContentView: View {
    @EnvironmentObject private var c: PrinterController
    @State private var selection: LabelFavorite.ID?

    var body: some View {
        NavigationSplitView {
            FavoritesSidebar(selection: $selection)
                .navigationTitle("Favorites")
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
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
            Button {
                Task { await c.refreshStatus() }
            } label: { Label("Status", systemImage: "arrow.clockwise") }
                .disabled(c.isBusy)

            if let s = c.status {
                HStack(spacing: 6) {
                    Circle().fill(TapeColor.color(s.tapeColor))
                        .overlay(Circle().stroke(.secondary.opacity(0.4)))
                        .frame(width: 14, height: 14)
                    Text("\(s.mediaWidthMM)mm")
                    Circle().fill(TapeColor.color(s.textColor)).frame(width: 8, height: 8)
                }
                .font(.callout)
            }
            Spacer()
            if c.isBusy { ProgressView().controlSize(.small) }
            Text(c.message).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}

// MARK: - Editor + preview

struct EditorPanel: View {
    @EnvironmentObject private var c: PrinterController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview").font(.headline)
            PreviewCard()

            if let r = c.rendered {
                Text(String(format: "%d raster lines · ~%.1f cm",
                            r.lengthDots, Double(r.lengthDots) * 0.149 / 10))
                    .font(.caption).foregroundStyle(.secondary)
            }

            GroupBox("Text") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $c.text)
                        .font(.system(size: 14))
                        .frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
                    Text("Use Return for a second line — the font shrinks to fit.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Picker("Font", selection: $c.fontName) {
                        ForEach(fontChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 280)
                }
                .padding(6)
            }

            HStack {
                Button {
                    c.saveFavorite()
                } label: { Label("Save to Favorites", systemImage: "star") }

                Spacer()

                Button {
                    Task { await c.printCurrent() }
                } label: {
                    Label("Print", systemImage: "printer.fill").frame(minWidth: 90)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(c.isBusy || c.text.isEmpty)
            }
        }
    }
}

struct PreviewCard: View {
    @EnvironmentObject private var c: PrinterController

    var body: some View {
        let tape = c.status.map { TapeColor.color($0.tapeColor) } ?? .white
        ScrollView(.horizontal, showsIndicators: true) {
            Group {
                if let cg = c.rendered?.preview {
                    Image(decorative: cg, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 72)
                        .padding(.horizontal, 8)
                } else {
                    Text("Type to preview").foregroundStyle(.secondary).frame(height: 72)
                }
            }
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .background(tape)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
    }
}

// MARK: - Favorites

struct FavoritesSidebar: View {
    @EnvironmentObject private var c: PrinterController
    @Binding var selection: LabelFavorite.ID?

    var body: some View {
        List(selection: $selection) {
            if c.favorites.isEmpty {
                Text("No favorites yet").foregroundStyle(.secondary)
            }
            ForEach(c.favorites) { fav in
                VStack(alignment: .leading) {
                    Text(fav.text.replacingOccurrences(of: "\n", with: " / "))
                        .lineLimit(1)
                    Text(fav.fontName).font(.caption2).foregroundStyle(.secondary)
                }
                .tag(fav.id)
                .contentShape(Rectangle())
                .onTapGesture { c.load(fav) }
            }
            .onDelete { idx in c.favorites.remove(atOffsets: idx) }
        }
        .frame(minWidth: 180)
    }
}
