import SwiftUI

/// In-app help, shown from the `?` toolbar button and the Help menu. Topics are
/// listed in a sidebar; each renders a short narrative on the right.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var topic: HelpTopic? = .gettingStarted

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(HelpTopic.allCases, id: \.self, selection: $topic) { t in
                    Label(t.title, systemImage: t.icon).tag(t)
                }
                .listStyle(.sidebar)
                .frame(width: 190)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        (topic ?? .gettingStarted).content
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(12)
        }
        .frame(width: 660, height: 560)
    }
}

enum HelpTopic: String, CaseIterable {
    case gettingStarted, cellEditing, formatting, tokens, cloud

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .cellEditing:    return "Cell Editing"
        case .formatting:     return "Formatting"
        case .tokens:         return "Substitution Tokens"
        case .cloud:          return "iCloud Sharing"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: return "printer"
        case .cellEditing:    return "square.on.square"
        case .formatting:     return "textformat"
        case .tokens:         return "number"
        case .cloud:          return "icloud"
        }
    }

    @ViewBuilder var content: some View {
        switch self {
        case .gettingStarted: HelpContent.gettingStarted
        case .cellEditing:    HelpContent.cellEditing
        case .formatting:     HelpContent.formatting
        case .tokens:         HelpContent.tokens
        case .cloud:          HelpContent.cloud
        }
    }
}

/// The help text for each topic, plus small layout helpers.
private enum HelpContent {
    @ViewBuilder static var gettingStarted: some View {
        head("Getting Started")
        body("BTLabel is designed for the **Brother P-touch PT-P300BT** label "
             + "printer, connected over Bluetooth. It is an independent product, not "
             + "affiliated with Brother, and does not work with other printers. Tape is "
             + "12 mm.")
        sub("First-time setup")
        step(1, "Power on the PT-P300 and load 12 mm tape.")
        step(2, "Open the **Bluetooth** menu in the macOS menu bar (or System Settings → "
                + "Bluetooth) and connect to the **PT-P300**.")
        step(3, "If macOS says you need to configure a printer (or opens Printers & "
                + "Scanners), click **Cancel**. BTLabel talks to the printer directly — "
                + "you do **not** add it as a system printer.")
        step(4, "Back in BTLabel, make sure the printer name matches, then click the "
                + "**Status** refresh button next to the name. When connected, you'll "
                + "see the loaded tape's width and color.")
        body("If Status can't connect, re-check the Bluetooth connection in the menu "
             + "bar and try again.")
    }

    @ViewBuilder static var cellEditing: some View {
        head("Cell Editing")
        body("A label is built from one or more **cells**, shown left to right in the "
             + "preview. Each cell is text, a symbol, or an image.")
        body("Turn on **Advanced** (top bar) to manage cells and per-cell formatting. "
             + "Basic mode keeps things simple — just type and print.")
        sub("Adding cells")
        bullet("**+Aa** adds a text cell.")
        bullet("**+Symbol** adds an icon — filter the Bootstrap icon set by name.")
        bullet("**+Image** imports a PNG, JPEG, SVG, or single-page PDF.")
        bullet("**Paste** (⇧⌘V) drops an image from the clipboard in as a new cell.")
        sub("Editing & arranging")
        bullet("Click a cell in the preview to select it; edit it in the panel below "
               + "(type, **Normal**/**Inverted** style, font, size).")
        bullet("**Drag** a cell left/right to reorder; drag it **off** the strip to delete.")
        bullet("**Right-click** a cell for Copy or Delete.")
        bullet("**Cell spacing** sets the gap between cells.")
        bullet("For photos, open **Adjust Image** for brightness, contrast, and dithering.")
    }

    @ViewBuilder static var formatting: some View {
        head("Formatting")
        body("Formatting applies per text cell. Turn on **Advanced** (top bar), select "
             + "a cell in the preview, and adjust its **Style** and **Size** in the "
             + "panel below.")
        sub("Style: Normal vs Inverted")
        bullet("**Normal** — text prints in the text color on the tape (for example, "
               + "black letters on white tape).")
        bullet("**Inverted** — the letters are reversed out of a solid block of ink: a "
               + "filled rectangle with the tape color showing through the text. Good "
               + "for headers, warnings, or making a section stand out.")
        sub("Size: Fit Text vs Consistent")
        bullet("**Fit Text** (default) — scales the cell to the largest size that fills "
               + "the tape height for *those exact letters*. Maximizes size, but a word "
               + "like “no” can look larger than “Jiffy” because it has no tall or "
               + "descending strokes.")
        bullet("**Consistent** — sizes by cap height instead of the specific letters, so "
               + "text is the same visual size across cells and across a batch of labels, "
               + "no matter which letters are used.")
        body("Tip: for a single bold word, **Fit Text** prints biggest. When you want "
             + "multiple cells — or a run of labels — to match, choose **Consistent**.")
    }

    @ViewBuilder static var tokens: some View {
        head("Substitution Tokens")
        body("Tokens are placeholders that fill in automatically when a label is shown "
             + "and printed. Type a token in any text cell — the **preview shows the "
             + "filled-in value**, but the saved label keeps the token, so it stays "
             + "current (great for dates and serial numbers).")
        body("A token is a slash plus a short code, and only takes effect when followed "
             + "by a space, punctuation, or the end of a line — so `/dog` prints "
             + "literally.")
        sub("Contact (from Settings ⚙)")
        bullet("`/n` name · `/p` phone · `/s` street · `/e` email")
        body("Enter these once in Settings and reuse them across every label.")
        sub("Counting (for multi-label runs)")
        bullet("`/i` current label number · `/c` total count")
        body("Example: `Box /i of /c` prints as “Box 3 of 25”. Set copies, start, and "
             + "total in **Print Settings**.")
        sub("Date")
        bullet("`/d` today (e.g. Jun 14, 2026)")
        bullet("`/d1` 6/14/26 · `/d2` 06/14/2026 · `/d3` 2026-06-14")
        bullet("`/d4` 14 Jun 2026 · `/d5` June 14, 2026")
    }

    @ViewBuilder static var cloud: some View {
        head("iCloud Sharing")
        body("Your **favorites**, **folders**, **print history**, and **contact info** "
             + "are stored in iCloud and sync automatically across every Mac signed in "
             + "to the same Apple ID.")
        bullet("Create or edit a label on one Mac and it appears on the others within a "
               + "moment — no manual export.")
        bullet("Organize favorites into folders; folder names, colors, and order sync too.")
        bullet("Contact fields update live — change your phone number on one Mac and it "
               + "refreshes on the others.")
        sub("Kept local to each Mac")
        bullet("The remembered last tape color (per printer).")
        bullet("The free-trial print count.")
        sub("Requirements")
        body("Sign in to the **same Apple ID** with **iCloud Drive** enabled on each "
             + "Mac. There's nothing else to set up.")
    }

    // MARK: - Layout helpers
    static func head(_ t: String) -> some View {
        Text(t).font(.title2).bold().padding(.bottom, 2)
    }
    static func sub(_ t: String) -> some View {
        Text(t).font(.headline).padding(.top, 6)
    }
    static func body(_ t: String) -> some View {
        Text(.init(t)).fixedSize(horizontal: false, vertical: true)
    }
    static func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").bold().frame(width: 18, alignment: .trailing)
            Text(.init(t)).fixedSize(horizontal: false, vertical: true)
        }
    }
    static func bullet(_ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").bold()
            Text(.init(t)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
