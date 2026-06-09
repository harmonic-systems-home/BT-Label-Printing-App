# BT Label Printing App

A native **macOS / iPadOS / iPhone** app for designing and printing labels on the
Brother P‑touch **PT‑P300BT** label maker over Bluetooth — with a full‑keyboard
editing experience, saved favorites, live tape status, font selection, and a
live print preview.

> **Compatibility / trademark notice.** This is an independent product, **not
> affiliated with, authorized by, sponsored by, or endorsed by Brother
> Industries, Ltd.** "Brother" and "P‑touch" are trademarks of their respective
> owners and are used here only to describe hardware compatibility.

## Status

🚧 Early scaffold. The Bluetooth transport approach is already validated on macOS
(native IOBluetooth RFCOMM connects reliably and prints); the app, protocol
layer, and UI are being built out. See [ARCHITECTURE.md](ARCHITECTURE.md).

## Planned features

- **Design with a real keyboard** — multi‑line text, font picker, sizing.
- **Live preview** of the final label before printing.
- **Live tape status** — shows the installed tape's color and width, read from
  the printer.
- **Favorites** — save and reprint common labels.
- **Images & graphics** — merge a PNG/PDF (icon, logo, QR) alongside text.
- **iCloud sync** — favorites and saved designs follow you across Mac, iPad,
  and iPhone.

## Platforms

| Platform | Bluetooth path | Status |
|---|---|---|
| **macOS 13+** | IOBluetooth RFCOMM (Bluetooth Classic / SPP) | ✅ Validated, reliable — primary target |
| iPadOS / iOS 16+ | — | 🔴 Blocked: the PT‑P300BT has **no BLE interface** (Classic SPP only), and iOS Classic SPP needs MFi. See [ARCHITECTURE.md](ARCHITECTURE.md#bluetooth-on-ios-resolved--ios-is-blocked-for-now). Shared layers stay cross‑platform so iOS is "transport‑away" if a path opens. |

## Supported hardware

- Brother P‑touch **PT‑P300BT** (12 mm tape). Other P‑touch Cube models may work
  with status/tape‑width handling added.

## Build & run

Requires Xcode 16+ / Swift 6 on macOS. The reusable core lives in the
**`PTouchKit`** Swift package (transport + clean-room protocol + raster encoder);
the SwiftUI app target is added on top in Xcode.

```bash
swift build          # build the package
swift test           # run protocol/raster unit tests
swift run ptsmoke    # connect to the printer over Bluetooth and read live status
```

`ptsmoke` is a connectivity smoke test — it pairs with the printer (`bt` name
match "PT-P300"), reads the 32-byte status, and prints the decoded tape
width/color and ready state. Open `Package.swift` in Xcode to work on the code.

## Implementation note (clean‑room)

The printer command/raster protocol here is implemented **independently** from
its publicly observable behavior — no third‑party source is incorporated. This
keeps the project's copyright clean and unencumbered.

## License

[PolyForm Perimeter 1.0.0](LICENSE.md) — you may use and modify the source for
any purpose **except** providing a product that competes with this software. See
[LICENSE.md](LICENSE.md).

Copyright © 2026 Rick Wilson.
