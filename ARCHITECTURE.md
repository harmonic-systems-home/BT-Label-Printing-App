# Architecture

> **Status (2026‑06):** the **macOS** app is built and **submitted to the App
> Store** (v1.0). iOS/iPadOS remain blocked at the transport layer (see below); the
> non‑transport layers are kept cross‑platform so a future Mac‑relay iOS app can
> reuse them.

A SwiftUI app sharing a layered codebase and one iCloud data store. The design is
layered so the platform‑specific part — the Bluetooth transport — is the only
thing that differs per OS.

```
┌─────────────────────────────────────────────────────────────┐
│  UI (SwiftUI, multiplatform)                                 │
│  Editor · Live Preview · Favorites · Printer/Tape Status     │
├─────────────────────────────────────────────────────────────┤
│  Data + Sync (SwiftData + CloudKit)                          │
│  LabelDesign · Favorite · Settings  ⟶ iCloud across devices  │
├─────────────────────────────────────────────────────────────┤
│  Rendering (Core Graphics / CoreText)                        │
│  Compose label image → 1‑bit raster (threshold / dither)     │
├─────────────────────────────────────────────────────────────┤
│  Protocol (clean‑room, pure Swift, platform‑agnostic)        │
│  Command set · raster (RLE) encode · 32‑byte status decode   │
├─────────────────────────────────────────────────────────────┤
│  Transport (PrinterTransport protocol) — platform‑specific   │
│  macOS: IOBluetooth RFCOMM   ·   iOS/iPadOS: CoreBluetooth    │
└─────────────────────────────────────────────────────────────┘
```

## 1. Transport layer (the only platform‑specific code)

Define one async protocol; provide a per‑platform implementation:

```swift
protocol PrinterTransport {
    func discover() async throws -> [PrinterDevice]
    func connect(to: PrinterDevice) async throws
    func send(_ bytes: Data) async throws
    func read(_ count: Int, timeout: Duration) async throws -> Data
    func disconnect() async
}
```

- **macOS — `RFCOMMTransport` (Bluetooth Classic / SPP).** Use `IOBluetooth`
  (`IOBluetoothDevice`, `IOBluetoothRFCOMMChannel`, SDP UUID `0x1101` for the SPP
  channel). This is the approach already proven to connect reliably and print —
  drain the run loop on close so `bluetoothd` tears the channel down cleanly.
- **iOS / iPadOS — `BLETransport` (CoreBluetooth).** `IOBluetooth` does **not**
  exist on iOS; see the open question below.

### Bluetooth on iOS: resolved — iOS is blocked for now

iOS apps **cannot** open a Bluetooth Classic / RFCOMM serial channel to an
arbitrary device. The only two options are:

1. **BLE (CoreBluetooth)** — works for any device exposing a BLE GATT service,
   no special enrollment.
2. **MFi / External Accessory** — required for Classic SPP on iOS, and only works
   if the *accessory* is MFi‑licensed and the app declares the manufacturer's
   protocol string. Not feasible for a third party without the manufacturer.

**Finding (2026‑06, empirical):** the PT‑P300BT is **Bluetooth Classic (SPP)
only — it does not expose a BLE interface.**

- On macOS it connects via an IOBluetooth **RFCOMM** channel using SDP UUID
  `0x1101` (Serial Port Profile) and appears in the Classic paired‑devices list.
- Two CoreBluetooth scans (including one right after a power‑cycle, showing all
  named *and* unnamed advertisers) found **no printer** — a device sitting next
  to the Mac would advertise at ~−50 dBm; nothing matched.
- Brother's published spec lists only "Interface: Bluetooth" (no version/profile).

**Consequence:** there is no BLE path on iOS, and Classic SPP on iOS needs MFi
with Brother's protocol string (how Brother's own iOS app connects). A
third‑party iOS/iPadOS build is therefore **not feasible without Brother's
involvement.** 

**Strategy:** ship **macOS first**. Keep the protocol, rendering, data, and UI
layers fully cross‑platform so the app is only a transport away from iOS. Do
**not** invest in a direct iOS Bluetooth transport.

### The viable iOS path: Mac as a print relay

Because the iOS app can reuse PTouchKit's renderer (CoreText/CoreGraphics work on
iOS) to produce the platform‑agnostic raster `rows`, the only thing it can't do
is the final Bluetooth hop. So the iPhone/iPad app **renders locally and sends
the raster job to the Mac**, which performs `PrintJob` over `RFCOMMTransport`:

- **Transport:** Bonjour/local‑network (`NWListener`/`NWBrowser`) for instant
  same‑Wi‑Fi printing; an optional CloudKit relay later for "print when away"
  (requires the Mac awake). 
- **Mac side:** a small `PrintRelayService` in the Mac app that advertises over
  Bonjour, accepts a job (rows + tape expectations), and prints.
- **iOS side:** the same editor/preview UI; "Print" sends the job to a discovered
  Mac instead of a local transport.

This sidesteps the MFi/BLE wall entirely. It's a sizable milestone (networking +
a second app target) and comes after the macOS app's core is solid.

## 2. Protocol layer (clean‑room, shared)

Pure Swift, no platform APIs, **implemented independently** from the printer's
observable behavior (keeps copyright clean):

- **Command set** — reset, set print parameters, page mode, get‑status, print.
- **Raster encoding** — 1‑bit lines, RLE (PackBits‑style) compression, the
  per‑line transfer framing.
- **Status decode** — parse the 32‑byte status reply: model, error flags, tape
  width, **tape color (foreground/background)**, phase (Ready / Printing).

The tape color + width from the status reply drive the live "what's loaded" UI.

## 3. Rendering layer (shared)

- Compose the label with **CoreText** (multi‑line, font picker, auto‑size to the
  tape's printable height) and **Core Graphics**; optionally `ImageRenderer` for
  SwiftUI‑composed previews.
- Convert to **1‑bit**: a tunable threshold (good for text/sprites) with optional
  Floyd–Steinberg dithering (for photos — though low‑res tape favors threshold).
- Image/PDF merge (icons, logos, QR) with a configurable gap before text.

The same renderer produces both the on‑screen **live preview** and the bytes fed
to the protocol layer — preview and print are guaranteed identical.

## 4. Data + iCloud sync (shared)

- **SwiftData** models with **CloudKit** sync (`ModelConfiguration(cloudKitDatabase:
  .automatic)`, container `iCloud.com.popperbiz.BTLabel`) so it works with zero
  custom sync code. As built:
  - `SavedLabelModel` — a label as `favorite` or `history`; cells stored as JSON in
    `cellsData`, plus `cellSpacingMM`, `tapeColor`/`textColor`, `folderID`, `sortIndex`.
  - `FavoriteFolder` — nestable folder (name, parentID, colorIndex, expanded, sortIndex).
  - `AppSettings` — contact fields (name/phone/street/email) for the tokens.
- Per‑device prefs (last tape color, free‑print count) stay local in `UserDefaults`.
- Requires the **iCloud (CloudKit)** capability + the sandbox `network.client`
  entitlement; `makeContainer()` falls back to a local store if iCloud isn't
  configured, so the app never crashes. Schema is deployed to **Production**.

## 5. UI layer (SwiftUI, adaptive)

- `NavigationSplitView` on Mac/iPad (sidebar: Favorites / New / Settings),
  compact stack on iPhone.
- **Editor** — text field(s), font picker, size/threshold/gap controls.
- **Live Preview** — renders the exact label image as you type.
- **Printer bar** — connection state + **installed tape color/width** from status.
- **Favorites** — saved designs, reprint, edit, sync via iCloud.

## Targets / project layout (as built)

```
BT-Label-Printing-App/
├─ Package.swift                 # PTouchKit package + CLI tools
├─ Sources/
│  ├─ PTouchKit/                 # LabelModel, LabelRenderer, LabelTokens,
│  │                             #   PTouchCommands, RasterEncoder, transports,
│  │                             #   PrinterStatus, BootstrapIcons, Resources/icons
│  ├─ ptsmoke/                   # connect + read status (CLI)
│  ├─ ptprint/                   # render + print / --preview (CLI)
│  └─ pticongen/                 # dev tool: rasterize SVGs → icon PNGs
├─ BTLabel/                      # Xcode app (only macOS functional)
│  └─ BTLabel/                   # BTLabelApp, PrinterController, ContentView,
│                                #   SavedLabelModel, StoreManager, PurchaseView, HelpView
├─ site/                         # btlabel.org static site (GitHub Pages via Actions)
├─ marketing/                    # App Store listing copy, screenshots, assets
└─ Icon/                         # app icon master
```

The transport is gated with `#if os(macOS)`; the package core (protocol, rendering,
tokens) is platform‑agnostic so it can be reused by a future iOS relay client.

## Open questions / next steps

1. ~~Confirm the PT‑P300BT's BLE interface.~~ **Resolved: no BLE (Classic SPP
   only) — iOS blocked for third parties. macOS‑first.** (See above.)
2. ~~Build the macOS `RFCOMMTransport`; wrap the clean‑room protocol + rendering
   behind it.~~ **Done — shipping.**
3. Tape‑size support beyond 12 mm (parity with the CLI's 12 mm assumption).
4. ~~App Store: iCloud container + entitlements; branding; license in listing.~~
   **Done — v1.0 submitted 2026‑06‑14.**
5. **Bluetooth reconnection robustness** — first print after a printer power‑cycle/
   replug can fail and recover on retry; needs a transport‑level retry / stale‑
   channel reset (see CLAUDE.md "Known issues").
