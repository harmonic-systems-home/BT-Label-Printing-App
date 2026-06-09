# Architecture

A SwiftUI **multiplatform** app (macOS, iPadOS, iOS) sharing one codebase and one
iCloud data store. The design is layered so the platform‑specific part — the
Bluetooth transport — is the only thing that differs per OS.

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

- **SwiftData** models with **CloudKit** sync (`ModelConfiguration` backed by the
  app's iCloud container) so it works with zero custom sync code:
  - `LabelDesign` — text, font, options, optional merged image, thumbnail.
  - `Favorite` — a pinned design for one‑tap reprint.
  - `AppSettings` — defaults (printer name, threshold, gap…).
- Tiny key/value prefs can use `NSUbiquitousKeyValueStore`.
- Requires the **iCloud (CloudKit)** capability and an iCloud container; gate
  sync behind the user being signed into iCloud, with a local‑only fallback.

## 5. UI layer (SwiftUI, adaptive)

- `NavigationSplitView` on Mac/iPad (sidebar: Favorites / New / Settings),
  compact stack on iPhone.
- **Editor** — text field(s), font picker, size/threshold/gap controls.
- **Live Preview** — renders the exact label image as you type.
- **Printer bar** — connection state + **installed tape color/width** from status.
- **Favorites** — saved designs, reprint, edit, sync via iCloud.

## Targets / project layout (planned)

```
BT-Label-Printing-App/
├─ Shared/            # protocol, rendering, data models, UI
├─ Transport/
│  ├─ RFCOMMTransport.swift   # macOS (IOBluetooth)
│  └─ BLETransport.swift      # iOS/iPadOS (CoreBluetooth)
├─ App/               # @main, scenes, platform entry points
└─ BT-Label-Printing-App.xcodeproj
```

One multiplatform app target (macOS + iOS destinations) with the transport file
compiled per‑platform via `#if os(macOS)` / `#if os(iOS)`.

## Open questions / next steps

1. ~~Confirm the PT‑P300BT's BLE interface.~~ **Resolved: no BLE (Classic SPP
   only) — iOS blocked for third parties. macOS‑first.** (See above.)
2. Build the macOS `RFCOMMTransport` from the validated approach; wrap the
   clean‑room protocol + rendering behind it.
3. Tape‑size support beyond 12 mm (parity with the CLI's 12 mm assumption).
4. App Store: iCloud container + entitlements; branding review (no Brother marks);
   PolyForm Perimeter license noted in the listing.
