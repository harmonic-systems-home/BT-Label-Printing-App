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

| Platform | Bluetooth path | Notes |
|---|---|---|
| macOS 13+ | IOBluetooth RFCOMM (Bluetooth Classic / SPP) | Validated, reliable |
| iPadOS / iOS 16+ | CoreBluetooth (BLE) — **pending hardware confirmation** | See the transport caveat in [ARCHITECTURE.md](ARCHITECTURE.md#bluetooth-on-ios-the-key-open-question) |

## Supported hardware

- Brother P‑touch **PT‑P300BT** (12 mm tape). Other P‑touch Cube models may work
  with status/tape‑width handling added.

## Build & run

Requires Xcode 16+ (Swift 6) on macOS.

```bash
open BT-Label-Printing-App.xcodeproj   # (project added in a later commit)
```

Select the **macOS** scheme (or **iOS** once the BLE transport lands) and run.

## Implementation note (clean‑room)

The printer command/raster protocol here is implemented **independently** from
its publicly observable behavior — no third‑party source is incorporated. This
keeps the project's copyright clean and unencumbered.

## License

[PolyForm Perimeter 1.0.0](LICENSE.md) — you may use and modify the source for
any purpose **except** providing a product that competes with this software. See
[LICENSE.md](LICENSE.md).

Copyright © 2026 Rick Wilson.
