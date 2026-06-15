# CLAUDE.md — BTLabel

Working notes for AI assistants (and humans) continuing this project.

## What this is
A native **macOS** app to design and print labels on the **Brother P-touch
PT-P300BT** over Bluetooth, with a full-keyboard editor, live preview, favorites,
symbols, and multi-label/token printing. Independent product — **not affiliated
with Brother**. License: **PolyForm Perimeter 1.0.0** (use/modify freely, no
competing product). **Submitted to the Mac App Store (v1.0 / build 3, 2026-06-14;
manual release).** Free to use with a one-time **$14.99** in-app unlock for
unlimited printing (5-print free trial). Source-available; site at **btlabel.org**.

## Repo layout
- **`Package.swift` + `Sources/`** — the `PTouchKit` Swift package (the reusable,
  mostly platform-agnostic core) plus two CLI tools.
  - `Sources/PTouchKit/`
    - `LabelModel.swift` — `LabelCell` (kind text/image/symbol, style normal/
      inverted, per-cell font/sizing), `SizingMode`, `CellStyle`. Codable.
    - `LabelRenderer.swift` (macOS-gated) — renders `[LabelCell]` → `RenderedLabel`
      (raster `rows` + `preview` CGImage + per-cell widths). CoreText/CoreGraphics.
    - `LabelTokens.swift` — `TextTokens.expand` for `/i /c /n /p /s /e /d`.
    - `PrinterStatus.swift` — decode the 32-byte status.
    - `PTouchCommands.swift` — Brother raster command builders (clean-room).
    - `RasterEncoder.swift` — PackBits + per-line framing.
    - `PrinterTransport.swift` — transport protocol + `queryStatus`.
    - `RFCOMMTransport.swift` (macOS) — IOBluetooth Classic/SPP transport.
  - `Sources/ptsmoke/` — connect + read status (CLI).
  - `Sources/ptprint/` — render + print (CLI). Flags: `--preview <png>` (render
    to PNG, no printer), `--symbol`, `--invert`, `--font`, `--sizing fit|cap`,
    `--image`, `--flip-length/--flip-width`. Prints raster dot-extent to stderr.
- **`BTLabel/`** — the Xcode app (`BTLabel.xcodeproj`, multiplatform target;
  only macOS is functional). Sources in `BTLabel/BTLabel/`:
  - `BTLabelApp.swift` — `@main`; SwiftData `ModelContainer` (CloudKit if
    configured, else local fallback).
  - `PrinterController.swift` — `@MainActor ObservableObject`: cells, selection,
    per-label `cellSpacingMM`, print run (copies/startIndex/totalCount/spacingMM/
    cutLine), contact fields (UserDefaults), token resolution, rendering, and
    multi-copy print assembly. Bluetooth runs on a **dedicated thread**
    (`BluetoothRunner`) and hops results to the main actor.
  - `ContentView.swift` — all SwiftUI views (status bar, interactive preview,
    cell editor, print settings, settings sheet, favorites sidebar).
  - `SavedLabelModel.swift` — SwiftData `@Model` (CloudKit-compatible: all
    defaults, no unique; cells stored as JSON in `cellsData`).

## Build / test / run
```bash
swift build                  # build the package
swift test                   # PTouchKit unit tests (status decode, PackBits)
swift run ptsmoke            # connect to printer, print status
swift run ptprint "Hi" --preview /tmp/x.png   # render a label to PNG (no printer)
swift run ptprint "Hi"       # actually print (printer on, paired)
# App:
xcodebuild -project BTLabel/BTLabel.xcodeproj -scheme BTLabel -destination 'platform=macOS' build
# or open Package.swift / the .xcodeproj in Xcode and ⌘R.
```
**Workflow tip:** after editing the renderer, use `ptprint --preview` and view the
PNG to verify output without wasting tape. Verify app compiles with `xcodebuild`.

## Printer / protocol facts (PT-P300BT)
- **Bluetooth Classic (SPP/RFCOMM) only — NO BLE.** Verified by CoreBluetooth
  scan. macOS connects via IOBluetooth RFCOMM (SDP UUID 0x1101, channel 1). The
  legacy `/dev/cu.*` serial path is unreliable; owning the channel + draining the
  run loop on close is the fix.
- **iOS is blocked for a third party** (Classic SPP on iOS needs MFi). The planned
  path is a **Mac print relay**: iOS renders raster rows (PTouchKit is reusable)
  and sends them to the Mac over Bonjour; the Mac does the BT hop. See ARCHITECTURE.md.
- **Geometry:** print head 128 dots (`bufferWidth`), printable **64 dots ≈ 9 mm**
  centred at offset **32** (dots 32–95) within 12 mm tape. ~0.149 mm/dot along
  length. Preview shows the full tape with the 9 mm band centred (printFraction
  0.745).
- **Rasterization:** each column of the readable image becomes one raster line
  (transpose); bit 1 = black; `dot = offset + row`.
- **Print sequence** (PrintJob): invalidate(64×0x00) → `ESC @` → `ESC i a 01`
  (raster) → `ESC i z` print-info [active **0xC4** = width|quality|recovery, media
  type, width mm, length mm, rasterLines LE32, 0, 0] → `ESC i K 0x08` (no chain)
  → `ESC i M 0x00` → `ESC i d` margin → `M 0x02` (TIFF/PackBits) → raster (`G`
  len+data / `Z` blank) → `0x1A` print+feed.
- **Status 32 bytes:** model[4]=0x72, errors[8|9], width mm[10], media type[11],
  status type[18], phase type[19]/num[20-21]. Tape colour[26]/text[27] (this
  model; not the spec's 24/25). Known-good ready bytes: `802042307230…0c01…0108…`.
- Protocol is a **clean-room** reimplementation of Brother's documented raster
  command set (the Python repo `~/Development/GitHub/PT-P300BT` was used to
  *observe* exact bytes, not copied).

## Rendering gotchas (learned the hard way)
- **SF Symbols in dark mode** render white-on-white as templates → rasterize via
  the **alpha channel** (fill black), appearance-independent. Symbols are cropped
  to ink and scaled to the band (their internal padding was clipping bottoms).
- **Normal text cells render tight** (no internal side padding); page margins come
  from the label end margin; cell spacing controls inter-cell gaps. Inverted text
  keeps padding (the box inset). At spacing 0, only the font side bearing remains
  (could be removed by ink-cropping text edges — minor TODO).
- **Image cells:** PNG/JPEG drawn without a CTM flip (the readGray convention has
  row 0 = top); PDF is y-up already. Don't re-add a flip.
- **Two spacings:** per-label **Cell spacing** (gap between cells, stored on the
  label) vs print-run **Label spacing** (gap between copies). Don't conflate.
- **Multi-copy print** (controller.printCurrent): each copy rendered tight
  (`endMarginDots: 0`), strip end margin = 18 dots, inter-label = `spacingMM`
  with optional 2-row black **cut line**.

## App conventions / state
- **CloudKit:** wired to a dedicated container **`iCloud.com.popperbiz.BTLabel`**
  (`makeContainer()` uses `.automatic`, falling back to local-only so it never
  crashes). Sandbox has `network.client` (ENABLE_OUTGOING_NETWORK_CONNECTIONS=YES)
  so CloudKit can reach iCloud. Synced models: `SavedLabelModel` (favorites +
  history), `FavoriteFolder`, `AppSettings` (contact fields). Schema is in the
  container's **Development** env and **deployed to Production**. Cross-Mac sync
  is **verified end-to-end** via TestFlight (favorites, folders, and contact
  fields live-update). Note: dev (Xcode) builds use the Development CloudKit env,
  TestFlight/App Store builds use Production — they don't share data, so test
  sync with TestFlight builds on all devices.
- Favorites = SwiftData (`@Query`), thumbnails rendered live, tokens expanded.
  History auto-logs distinct printed labels (capped, promotable to favorites).
- Contact fields are SwiftData (`AppSettings`, iCloud-synced); writes are
  **debounced ~700ms** and flushed when the Settings sheet closes (avoids a
  CloudKit export per keystroke). Copies/numbering are per-session.
- **Basic/Advanced UI:** `@AppStorage("advancedUI")` (default off) gates the
  add-cell buttons, per-cell controls row, and preview status row. Basic keeps
  preview + text box + collapsed Print Settings; the text box stays so /n /e
  tokens remain visible/editable.
- **Symbols:** Bootstrap Icons (MIT), pre-rasterized to PNGs in
  `Sources/PTouchKit/Resources/icons/`, with a text filter. (Categories/search
  beyond the filter are still open.)
- **Tokens:** a token applies only at a boundary (space/punctuation/EOL), not when
  followed by a letter or digit. Date variants `/d` (medium) and `/d1`–`/d5`.
- **App icon:** generated from `Icon/Icon Master.png` into `AppIcon.appiconset`
  (macOS 16–512 @1x/2x + 1024; the 1024 is alpha-free for App Store validation).

## Open refinements / roadmap
**Done:** Folders for Favorites (drag-and-drop, synced) · Bootstrap Icons (MIT)
with filter · app icon · dedicated CloudKit container + sandbox network entitlement
· Basic/Advanced UI · `/d1`–`/d5` date tokens + token boundary fix · debounced
contact saves · **CloudKit schema deployed to Production + cross-Mac sync verified
via TestFlight** (incl. live contact-field refresh) · `LSApplicationCategoryType`
(Productivity) + `ITSAppUsesNonExemptEncryption=NO` for App Store upload.

**Brand name:** **BTLabel** (final).

**Submitted to App Store review 2026-06-14** (v1.0 build 3, manual release). Done:
IAP `com.popperbiz.BTLabel.unlock` ($14.99, Family Sharing) created + reviewed;
listing copy/keywords/screenshots (`marketing/`); btlabel.org site (support +
privacy) via GitHub Pages; `support@btlabel.org` email; App Privacy = Data Not
Collected; demo video for the print step.

**Post-approval to-dos:**
- Click **Release** (manual release was chosen).
- Generate **IAP promo codes** (only available after approval).
- Update the App Store link on btlabel.org's landing page once live.

**Recently fixed:**
- **Bluetooth reconnection after power-cycle** (was: first connect failed with
  IOReturn `0xe00002bc`, needed manual retries). `RFCOMMTransport.connect` now
  wakes the baseband link (`device.openConnection()`) before opening RFCOMM,
  refreshes the SDP query on retries, and retries until the timeout (app uses 25s).
  Verified with `ptsmoke` connecting on the first try right after a power-cycle.

**Nice-to-have / future:**
- iPhone/iPad app via the **Mac relay** (Bonjour) — reuses PTouchKit rendering.
- Tape sizes other than 12 mm (status already carries width).
- Symbol **categories** (text filter exists; categories don't).
- *(Optional)* ink-crop text left/right to remove side bearing at spacing 0.
- *(Optional)* flush contact edits on app termination (force-quit-with-sheet-open
  edge case).

## Commit style
Conventional, imperative subject; end body with:
`Co-Authored-By: Claude <noreply@anthropic.com>`. Verify `xcodebuild` succeeds
before committing app changes; `swift test` for package logic.
