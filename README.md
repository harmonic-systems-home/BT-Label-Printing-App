# BTLabel

A native **macOS** app for designing and printing labels on the Brother P‑touch
**PT‑P300BT** label maker over Bluetooth — full‑keyboard text editing, built‑in
icons, images, an exact live preview, tape‑color matching, favorites with folders,
print history, substitution tokens, and iCloud sync across your Macs.

Website: **[btlabel.org](https://btlabel.org)** · Support: **[btlabel.org/support.html](https://btlabel.org/support.html)**

> **Compatibility / trademark notice.** This is an independent product, **not
> affiliated with, authorized by, sponsored by, or endorsed by Brother
> Industries, Ltd.** "Brother" and "P‑touch" are trademarks of their respective
> owners and are used here only to describe hardware compatibility.

## Status

**Live on the [Mac App Store](https://apps.apple.com/app/id6780239795)**, with a
free edition on [GitHub Releases](https://github.com/harmonic-systems-home/BT-Label-Printing-App/releases/latest).
The app is feature‑complete on macOS: native IOBluetooth RFCOMM transport,
clean‑room raster protocol, and the full SwiftUI editor. See
[ARCHITECTURE.md](ARCHITECTURE.md).

## Editions & pricing

| | **Mac App Store** | **Free (GitHub release)** |
|---|---|---|
| Price | 5‑print free trial, then a one‑time **$14.99** unlock (Family Sharing) | Free |
| Printing | Unlimited once unlocked | Unlimited |
| iCloud sync (favorites, folders, history, settings) | ✅ | — stored on this Mac |
| Updates | Automatic | Download new releases yourself |
| Install | [Mac App Store](https://apps.apple.com/app/id6780239795) | Signed, notarized zip from [Releases](https://github.com/harmonic-systems-home/BT-Label-Printing-App/releases/latest) |

Both editions are built from this repo; the difference is one build flag (see
[Editions](#editions-build-flag)). The app is **source‑available**, so you may also
build the free edition yourself.

## Features

- **Editor** — multi‑line text, font picker, Normal/Inverted styles, smart sizing.
  Basic mode for quick labels; Advanced mode for multi‑cell layouts.
- **Live preview** — the exact 1‑bit image that will print (preview == print).
- **Icons** — bundled Bootstrap Icons (MIT) with instant text search.
- **Images** — PNG/JPEG/SVG/PDF, or paste straight from the clipboard; brightness/
  contrast and Floyd–Steinberg dithering for photos.
- **Tape‑color matching** — preview is tinted to the loaded (or chosen) tape.
- **Live tape status** — reads the installed tape's color/width from the printer.
- **Favorites with folders** + automatic **print history**.
- **Substitution tokens** — `/n /p /s /e` (contact), `/i /c` (numbering), `/d`
  plus `/d1`–`/d5` (dates); multi‑copy printing with auto‑numbering.
- **iCloud sync** (App Store edition) — favorites, folders, history, and settings
  follow you across Macs.

## Platforms

| Platform | Bluetooth path | Status |
|---|---|---|
| **macOS 26.5+** (the `PTouchKit` package alone builds on macOS 13+) | IOBluetooth RFCOMM (Bluetooth Classic / SPP) | ✅ Shipping (primary target) |
| iPadOS / iOS 16+ | — | 🔴 Blocked: the PT‑P300BT has **no BLE** (Classic SPP only), and iOS Classic SPP needs MFi. A future **Mac‑relay** path (Bonjour) could reuse the rendering layer. See [ARCHITECTURE.md](ARCHITECTURE.md#bluetooth-on-ios-resolved--ios-is-blocked-for-now). |

## Supported hardware

- Brother P‑touch **PT‑P300BT** (12 mm tape). Other P‑touch Cube models may work
  with status/tape‑width handling added.

## Build & run

Requires Xcode 16+ / Swift 6 on macOS. The reusable core lives in the
**`PTouchKit`** Swift package (transport + clean‑room protocol + raster encoder);
the SwiftUI app target (`BTLabel/BTLabel.xcodeproj`) is built on top.

```bash
swift build              # build the PTouchKit package
swift test               # run protocol/raster/token unit tests
swift run ptsmoke        # connect over Bluetooth and read live status
swift run ptprint "Hi" --preview /tmp/x.png   # render a label to PNG (no printer)
swift run ptprint "Hi"   # render text and print a real label, end‑to‑end

# App:
xcodebuild -project BTLabel/BTLabel.xcodeproj -scheme BTLabel -destination 'platform=macOS' build
```

`ptsmoke` is a connectivity smoke test — it pairs with the printer (name match
"PT-P300"), reads the 32‑byte status, and prints the decoded tape width/color and
ready state. Open `Package.swift` or the `.xcodeproj` in Xcode to work on the code.

To build the app with your own Apple ID, open `BTLabel/BTLabel.xcodeproj`, choose
your team under **Signing & Capabilities** (change the bundle identifier if Xcode
reports it's taken), and press ⌘R.

### Editions (build flag)

| Configuration | `APP_STORE` flag | Print trial + in‑app purchase | iCloud entitlements | Used by |
|---|---|---|---|---|
| Debug / Release | — | — (unlimited) | — (local storage) | ⌘R, `xcodebuild build`, GitHub release |
| **AppStore** | ✅ | ✅ | ✅ | Product → Archive, **BTLabel App Store** scheme |

- **App Store:** Product → Archive. Both schemes archive the AppStore configuration.
  Use the **BTLabel App Store** scheme to run that edition locally (trial, StoreKit
  test purchases, iCloud).
- **GitHub release:** `scripts/release-github.sh` archives the Release
  configuration, exports it with Developer ID, notarizes, and staples. It writes
  `build/github-release/BTLabel-<version>.zip` (setup notes are in the script).

## Implementation note (clean‑room)

The printer command/raster protocol is implemented **independently** from its
publicly observable behavior — no third‑party source is incorporated. This keeps
the project's copyright clean and unencumbered.

## License

[PolyForm Perimeter 1.0.0](LICENSE.md) — you may use and modify the source for any
purpose **except** providing a product that competes with this software.

Copyright © 2026 Rick Wilson.
