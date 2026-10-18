# MacShell - New Features & Updates

This document summarizes the new widgets, design refinements, and performance optimizations introduced in this update.

---

## 🚀 New Widgets

### 1. System Monitor Widget (`SystemMonitorWidget.qml` & `sysmon_reader.py`)
Inspired by Apple Activity Monitor and macOS Sonoma widgets, this widget provides real-time hardware telemetry:
- **Small (168×168)**: 2×2 quad circular gauges for **CPU**, **GPU**, **RAM**, and **Disk**.
- **Medium (358×168)**: Dual circular gauges for CPU & RAM usage, a styled storage bar with free space, and metric cards for GPU utilization, thermal temperatures (°C), and live network throughput.
- **Large (358×354)**: Comprehensive system dashboard with circular gauges, detailed RAM/Storage allocation bars, load status, and sensor readouts.
- **Efficient Backend**: `sysmon_reader.py` samples `/proc`, `sysfs`, and GPU interfaces with low CPU footprint.

### 2. Stocks & Cryptocurrency Widget (`StocksWidget.qml` & `stocks_fetcher.py`)
Live market tracking styled after Apple Stocks:
- **Small (168×168)**: Highlights a chosen asset (e.g., BTC, ETH, SOL, AAPL, NVDA) with real-time price, 24h change pill, interactive cycling switcher (`⇄`), and an area-gradient sparkline curve.
- **Medium (358×168)**: Watchlist displaying top crypto and equity assets, responsive mini sparklines, formatted currency numbers, and dynamic green/red change badges.
- **Large (358×354)**: Featured hero asset with an expanded sparkline chart on top and a full markets watchlist below.
- **Backend Fetcher**: `stocks_fetcher.py` queries public CoinGecko & financial APIs with rate-limited caching to save bandwidth and compute.

### 3. Animated GIF Widget (`GifWidget.qml`)
- Allows users to display animated GIF and WebP loops on their desktop.
- **Smart GPU Throttling**: Automatically halts playback when windows cover the desktop, reducing GPU/CPU consumption to 0%.

### 4. Custom Photo Widget (`ImageWidget.qml`)
- Display personal photos cropped with Apple-standard rounded corner squircle masks.

### 5. Battery Widget (`BatteryWidget.qml` & `battery_reader.py`)
- Clean circular battery indicator with charging animations, power source details, and connected accessory tracking.

---

## 🎨 UI Refinements & Apple Design Language

- **Canonical macOS Geometry**:
  - Unified sizing system: Small (`168×168`), Medium (`358×168`), and Large (`358×354`).
  - Standardized squircle corner radius (`radiusPx: 28 * s`) matching Apple macOS Sequoia & Tahoe design specs.
- **Generous Edge Padding**:
  - Content margins adjusted to `18px - 20px` to prevent text, buttons, and sparkline curves from touching or clipping into curved corners.
- **Liquid Glass Shader Integration**:
  - Full vector2d uniform compatibility for `liquidglass.frag` with drop-shadow padding (`gl.padPx`) and rim highlights.
- **Clean Localization**:
  - 100% English codebase, headers, and UI strings for upstream merge readiness.

---

## ⚡ Performance Optimizations

1. **GPU & CPU Efficiency**:
   - Decreased unnecessary QML bindings and timer frequencies.
   - Asynchronous Python collectors with `StdioCollector` preventing UI thread stutters.
   - Resource-aware rendering when desktop is obscured.
2. **Safe Settings Management**:
   - Dynamic widget addition, reordering, and removal via MacDock settings panel.
