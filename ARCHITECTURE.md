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

### Bluetooth on iOS: the key open question

iOS apps **cannot** open a Bluetooth Classic / RFCOMM serial channel to an
arbitrary device. The only two options are:

1. **BLE (CoreBluetooth)** — works for any device that exposes a BLE GATT
   service, no special enrollment. We'd discover the printer's service/
   characteristic UUIDs and write the same protocol bytes to a characteristic.
2. **MFi / External Accessory** — required for Classic SPP on iOS, and only works
   if the *accessory* is enrolled in Apple's MFi program for your app. Not
   feasible for a third party.

**So iOS support hinges on whether the PT‑P300BT exposes a BLE interface.** The
official Brother iOS app connects to this printer, so a phone‑reachable path
exists — almost certainly BLE. **Action item before committing to the iOS
target:** scan the powered‑on printer with a BLE explorer (e.g. *LightBlue* /
*nRF Connect*) and record its service + writable/notify characteristic UUIDs and
MTU. If BLE is confirmed, `BLETransport` is straightforward and the protocol/
rendering/UI layers above it are 100% shared. (BLE could even be used on macOS
too, unifying the transport — worth evaluating.)

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

1. **Confirm the PT‑P300BT's BLE interface** (service + characteristic UUIDs).
   This gates the entire iOS/iPadOS target.
2. Decide whether to use BLE on macOS too (one transport) or keep RFCOMM there.
3. Tape‑size support beyond 12 mm (issue parity with the CLI's assumptions).
4. App Store: iCloud container + entitlements; branding review (no Brother marks).
