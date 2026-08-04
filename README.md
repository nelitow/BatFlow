<div align="center">

# ⚡️ BatFlow

### Next-Generation Power Flow Telemetry & Battery Monitor for macOS

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-blue.svg?style=flat-square&logo=apple)](https://www.apple.com/macos)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/nelitow/BatFlow?include_prereleases&label=download&style=flat-square)](https://github.com/nelitow/BatFlow/releases/latest)

<br/>

## [⬇️ Download BatFlow for macOS](https://github.com/nelitow/BatFlow/releases/latest/download/BatFlow-macOS.zip)

> **Download · Unzip · Double-click to run.** No installer needed.
> Requires macOS 14 (Sonoma) or later.

<br/>

<img src="assets/hero.jpg" alt="BatFlow Interface Banner" width="840" />

</div>

---

## 💡 Overview

**BatFlow** is an open-source, lightweight native macOS menu bar application designed to replace legacy tools like BatFi on modern macOS (macOS 14, 15, 16, 27+).

Built with Swift, SwiftUI, and low-level IOKit & Apple SMC interfaces, BatFlow provides real-time power distribution breakdown, Apple Silicon SMC battery temperature sensing, USB-C output port wattage inspection, and historical telemetry charts.

> [!NOTE]
> **Designed for macOS 15 & 27+**
> Recent macOS releases include native system battery charge management (such as the 80% charging limit). **BatFlow intentionally focuses on deep observability and rich visual telemetry** — real-time power flow graphs, per-port USB-C wattage inspection, SMC thermal monitoring, and charge ETA — without interfering with macOS native power management routines.

---

## ✨ Features

- ⚡️ **Real-Time Charge Flow Graph** — Animated node diagram showing live power split between AC Charger input, Mac/CPU usage, Battery charge/discharge rate, and USB-C Output Ports
- 🌡 **Precision SMC Battery Temperature** — Reads Apple Silicon SMC keys (`TB0T`, `TB1T`, `TB2T`) for exact temperature in °C or °F
- 🔌 **USB-C Output Port Wattage Inspector** — See exactly how many watts you're delivering to a connected iPhone, iPad, or accessory
- ⏱ **Charge / Drain ETA** — Instant estimate of time until full charge or full battery drain
- 📊 **Rolling Telemetry Charts** — Historical graphs tracking power draw and battery level over time using Swift Charts
- ⚙️ **Customizable Status Bar** — Choose your menu bar format, polling interval, and temperature unit. Health & cycle count hidden by default (toggle in settings)
- 🍃 **Zero Dependencies** — 100% native Swift & SwiftUI, ultra-low CPU and memory footprint

---

## 📦 Installation

### Option A — Direct Download (Recommended)

1. **[⬇️ Download BatFlow-macOS.zip](https://github.com/nelitow/BatFlow/releases/latest/download/BatFlow-macOS.zip)**
2. Unzip the file
3. Drag `BatFlow.app` to your **Applications** folder (optional but recommended)
4. Double-click to launch — BatFlow will appear in your menu bar

> If macOS shows a security warning, go to **System Settings → Privacy & Security** and click **Open Anyway**.

### Option B — Build from Source

Requirements: macOS 14.0+, Xcode 15+ / Command Line Tools.

```bash
git clone https://github.com/nelitow/BatFlow.git
cd BatFlow

mkdir -p build/cache BatFlow.app/Contents/MacOS BatFlow.app/Contents/Resources

swiftc -module-cache-path build/cache \
  -framework IOKit -framework AppKit -framework SwiftUI -framework Charts \
  -parse-as-library -O \
  -o BatFlow.app/Contents/MacOS/BatFlow \
  Sources/BatFlow/*.swift

cp Info.plist BatFlow.app/Contents/Info.plist
codesign -s - --force --deep BatFlow.app
open BatFlow.app
```

---

## 🛠 Architecture

| Layer | Detail |
|---|---|
| **Battery State** | `AppleSmartBattery` IOKit — level %, voltage, amperage, charger wattage, port output, cycle count, health |
| **Temperature** | `AppleSMC` — float keys `TB0T` / `TB1T` / `TB2T` averaged for precision |
| **System Power** | SMC key `PSTR` for real-time CPU/board power draw |
| **UI** | SwiftUI + Swift Charts, zero third-party dependencies |
| **Release CI** | GitHub Actions — builds and publishes `BatFlow-macOS.zip` on every push to `main` |

---

## 🚀 CI/CD

Every merge to `main` automatically:
1. Compiles `BatFlow.app` on `macos-latest`
2. Ad-hoc signs and packages `BatFlow-macOS.zip`
3. Publishes it as the **latest** GitHub Release — always a fresh download at the link above

Tag a version (`git tag v1.x.x && git push origin v1.x.x`) to cut a numbered stable release.

---

## 📄 License

BatFlow is open-source under the [MIT License](LICENSE).

---

<div align="center">
Made with ❤️ for macOS · <a href="https://nelitow.github.io/BatFlow">Website</a> · <a href="https://github.com/nelitow/BatFlow/releases">Releases</a>
</div>
