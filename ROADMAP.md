# MacShell macOS Feature Parity Roadmap

This roadmap tracks features needed to bring **MacShell** (Hyprland + Quickshell) closer to full feature parity with modern **macOS (Sequoia / Tahoe)**.

Items are grouped by area. Each item includes a brief note on the current state in the codebase to make picking up any task straightforward.

---

## Quick Wins (Partially Implemented)

- [x] **Expose remaining `ExtraWidgets.qml` widgets** — `batteries`, `notes`, `photos`, `alarms`, and `stocks` from `MacShell/ExtraWidgets.qml` are now registered in `MacShell/MacWidgets.qml` and selectable in Settings.
- [x] **Wire built-in `WindowDecor.qml` & `MinimizeFx.qml` into `shell.qml`** — Both components are now instantiated in `MacShell/shell.qml` (with opt-in Settings controls in Desktop & Dock → Behavior, `windecor` / `minimize` IPC handlers, and Dock/Menu Bar minimize & restore integration).
- [x] **Render D-Bus notification action buttons & inline reply** — `MacShell/MacBar.qml` now renders named D-Bus action buttons and an inline reply box on both toasts and Notification Center cards.
- [x] **Search System Settings panes in Spotlight** — Spotlight now searches `settingsPanes` (`name` and `keys` from `MacShell/MacDock.qml`) and opens the matched Settings pane directly.

---

## 1. Window Management & Multitasking

- [x] **Mission Control** — `MacShell/MissionControl.qml` provides an overview of open windows across workspaces, a top Spaces bar with proportional workspace thumbnails, drag-and-drop of windows between workspaces, creating/closing workspaces, and `missioncontrol` IPC (`SUPER + Up`).
- [x] **App Exposé** — Spreads out all open windows of a single application (plus a bottom tray for minimized windows) via `expose` IPC (`SUPER + Down`), Dock right-click (*Show All Windows*), Shift+Click on Dock app icons, Menu Bar (*Window → App Exposé*), and Hot Corners.
- [x] **Stage Manager** — Opt-in left-edge strip in `MacShell/WindowMgmt.qml` grouping inactive apps into live-thumbnail stages (`special:stage`), with click-to-switch, Shift+Click / `+` merge into the active stage, optional auto-hide, Settings & Menu Bar toggles, `stagemanager` IPC, and automatic window restore on disable/exit.
- [x] **macOS Window Tiling & Snap-to-Edges** — Pure geometry layout engine (`MacShell/WindowMgmt.js` + `MacShell/WindowMgmt.qml`) with halves, quarters, thirds, Fill, Center, Left & Right pair arrangement, pre-tile Restore, live edge/corner drag-snap preview in `WindowDecor.qml`, green traffic-light hover tile menu, *Window → Move & Resize* menu items in `MacBar.qml`, and `tile` IPC.
- [x] **Hot Corners (Active Screen Corners)** — Configurable per-corner triggers (`Mission Control`, `App Exposé`, `Show Desktop`, `Notification Center`, `Quick Note`, `Lock Screen`, `Start Screen Saver`, `Spotlight`) with dwell delay, fullscreen suppression, zero-window idle overhead, and built-in floating Quick Note sheet.
- [x] **Click Wallpaper to Reveal Desktop** — Clicking empty desktop space in `MacShell/Desktop.qml` (configurable: *Always* / *Stage Manager* / *Off*) moves open workspace windows aside (`special:desktop-peek`) with a macOS-style edge vignette frame and restores them on the next click, edge click, or new window (`desktop` IPC).

---

## 2. Menu Bar & Control Center

- [x] **Real Global Menu (`DBusMenu`)** — `MacShell/assets/appmenu-bridge.py` + `MacShell/MacBar.qml` claim `com.canonical.AppMenu.Registrar`, query real `com.canonical.dbusmenu` menu trees (with nested submenus, shortcuts, and checkmarks) for the focused app with automatic fallback to built-in menus, and add a macOS-style searchable *Help* menu filtering all active app menu items.
- [x] **Auto-hide Menu Bar** — Configurable in *Settings → Menu Bar* (`Never` / `Full Screen` / `Always`) and via `menubar autohide` IPC; drops `exclusiveZone` when hidden and slides smoothly back in when hovering the top screen edge.
- [x] **Reorder & Hide Menu Bar Items** — Hold `Alt` (or `Meta`) and drag status items in `MacShell/MacBar.qml` (`MacShell/MenuBar.js`) to reorder them horizontally (persisted in `barRightOrder`), or drag downward off the bar to hide them.
- [x] **Live Activities in Menu Bar** — macOS Tahoe–style compact status pills in the menu bar (`MacShell/MenuBar.js` + `MacShell/MacBar.qml`) for active `ClockApp` timers/stopwatches/ringing alarms, screen recordings, and active Discord voice calls.
- [x] **Real Focus Modes** — `MacShell/FocusModes.js`, *Settings → Focus* (`MacShell/SettingsWindow.qml`), and Control Center's Focus sub-page provide customizable profiles (`Do Not Disturb`, `Work`, `Sleep`, `Personal`, `Gaming`) with schedules (including overnight ranges), per-app notification allowlists, optional per-Focus wallpapers, Game Mode linking, and `focus` IPC.
- [x] **Additional Control Center Modules** — Added Keyboard Brightness slider (`kbbacklight`), Screen Mirroring / Display Casting tile + monitor/cast sub-page (`mirroring`), and AirDrop / Nearby Share toggle (`airdrop`, LocalSend / KDE Connect / Warpinator) to `ccCatalog` in `MacShell/MacBar.qml`.

---

## 3. Dock

- [x] **Dock Folders / Stacks** — Pin folders (e.g. Downloads, Documents, Pictures) next to Trash in `MacShell/MacDock.qml` (`MacShell/DockLogic.js`) with switchable Fan, Grid, and List popovers, right-click view switching, and Settings controls.
- [x] **Left & Right Dock Positioning** — `dockPosition` (`bottom` | `left` | `right`) in `MacShell/MacDock.qml`, `MacShell/Desktop.qml`, *Settings → Dock*, and `dock position` IPC adapts PanelWindow anchors, vertical Grid layout, Y-axis magnification, glass backdrop offsets, and popovers.
- [x] **Notification Badges** — Red macOS unread counters on Dock app icons fed by `MacBar.qml`'s per-app unread notification map (`notifAppCounts`, auto-cleared on app focus or Notification Center open) plus `dock badge` IPC overrides.
- [x] **Recent Apps Section** — Persisted `recentApps` section between pinned/running apps and Trash showing the last N recently closed unpinned apps, with *Keep in Dock* and *Remove from Recent* context actions and a Settings toggle.
- [x] **Drag & Drop Files onto Dock App Icons** — Dragging Desktop icons (via `Desktop.qml` `appDropHit`/`dropFilesOnApp`) or external file-manager URLs (via Qt `DropArea`) onto any Dock app icon opens them with that app (and onto Dock folders moves them in).

---

## 4. Spotlight (macOS Tahoe Parity)

- [x] **Full-Text & Metadata File Search** — `MacShell/assets/spotlight-search.py` upgrades `MacBar.qml` file search with ranked filename + ripgrep full-text content search (showing matching line snippets), file size/mtime metadata, and `pdftotext` PDF excerpt support.
- [x] **Quick Look Preview Pane** — Split-view preview pane (`spPreviewPane` in `MacShell/MacBar.qml`) renders images, screenshots, text/code/PDF excerpts, directory listings, file metadata, and Open / Copy Path actions alongside Spotlight results.
- [x] **Spotlight Actions & Quick Keys** — Expanded *Actions* tab with system/window/media commands, user-defined `spotlightActions`, and quick keys (`t 5m` / `timer`, `note`, `remind`, `focus`) powered by `MacShell/Spotlight.js`.
- [x] **Inline Knowledge Cards** — Live currency conversion (`100 USD to EUR`, `50€ in $` with cached FX rates), dictionary definitions (`define <word>`), and inline weather (`weather`) & stock (`stock AAPL` / `$AAPL`) summary cards in Spotlight.

---

## 5. Notifications, Widgets & Desktop

- [x] **Grouped / Stacked Notifications** — `MacShell/DesktopWidgets.js` + `MacShell/MacBar.qml` collapse multiple notifications from the same app into expandable stacks with a `+N more` / `Show less` toggle pill.
- [x] **Combined Notification Center + Widgets Sidebar** — Clicking the Menu Bar clock opens the unified Notification Center + Widgets Sidebar (`notifPop` + `notifWidgetsStrip` showing mini Calendar and Weather cards alongside notifications; right-click opens standalone Calendar).
- [x] **Multi-Monitor Desktop Widgets** — Lifted the primary-monitor-only limit in `MacShell/MacWidgets.qml` so widgets persist a `screen` property, render on all connected displays, and can be moved across monitors in edit mode.
- [x] **Desktop Stacks** — Right-click Desktop → *Use Stacks* (`Kind` / `Date`) groups desktop files into expandable stacks via `MacShell/DesktopWidgets.js` + `MacShell/Desktop.qml` with a floating stack popover.
- [x] **System-Wide Quick Look (`Space`)** — `MacShell/QuickLook.qml` provides an instant floating Liquid Glass preview for images, PDFs, code/markdown/text, folders, and media metadata via Desktop `Space`/Quick Preview, Spotlight Quick Look button, and `quicklook` IPC.

---

## 6. Screenshots, System Dialogs & Settings

- [x] **Floating Screenshot Thumbnail** — `MacShell/CaptureSuite.qml` displays a bottom-right preview thumbnail after capture (`MacBar.qml` `shotSaveProc`) with hover pause, auto-dismiss, Copy, and click-to-Markup.
- [x] **Built-in Markup / Annotation Editor** — `MacShell/CaptureSuite.qml` provides Canvas annotation tools (Arrow, Box, Pen, Redact, Text), color palette, Undo, and Save & Copy directly on captured screenshots (`capture markup <path>`).
- [x] **Capture Toolbar (`Cmd+Shift+5` style)** — Bottom-center Liquid Glass bar in `MacShell/CaptureSuite.qml` (`capture toolbar` IPC) switching between Entire Screen, Window, Selection, and Screen Recording with 0s/5s/10s countdown delay.
- [x] **Liquid Glass Polkit Auth Agent** — `MacShell/PolkitAuth.qml` provides a native macOS-style authentication prompt with password verification, `fprintd` fingerprint detection, and `polkit` IPC.
- [x] **Force Quit Dialog & Native Activity Monitor** — `MacShell/SystemDialogs.qml` adds a `Force Quit Applications` dialog (`forcequit` IPC / Apple menu) and a native tabbed Liquid Glass Activity Monitor (`activity` IPC / Menu Bar System Monitor / Apple menu).
- [x] **Missing System Settings Panes** (`MacShell/SystemSettingsPanes.js`, `MacShell/MacDock.qml`, `MacShell/SettingsWindow.qml`, all searchable in Spotlight):
  - [x] **Storage** — Color-coded disk usage breakdown bar and Trash / MacShell cache cleanup helpers.
  - [x] **Privacy & Security** — Active mic/camera/screen consumers and firewall (`ufw`/`firewall-cmd`) status.
  - [x] **Accessibility** — Reduce Motion, Hyprland screen zoom slider, and cursor size controls.
  - [x] **Login Items / Autostart** — Manage `~/.config/autostart/*.desktop` entries (`Hidden` toggle).
  - [x] **Date & Time** — Timezone display, NTP toggle (`timedatectl`), and 24-hour/date/seconds options.
  - [x] **Printers & Scanners** — CUPS printer status (`lpstat`) and CUPS Admin quick launch.
  - [x] **Sharing** — Hostname and SSH, SMB/Samba, and Screen Sharing (`wayvnc`) controls.
  - [x] **System Software Update** — Distro package update checker (`checkupdates`/`pacman`/`apt`/`dnf`) alongside MacShell updates.

---

## 7. Ecosystem & Linux Integrations

- [ ] **AirDrop / Continuity / Phone Mirroring** — Integrate KDE Connect / GSConnect, LocalSend, and `scrcpy` into the Control Center, share menus, and notifications for file drops, universal clipboard, and phone mirroring.
- [ ] **Time Machine UI** — Visual snapshot browser and file restore interface backed by Btrfs + Snapper (or Timeshift).
- [ ] **Aerial Screensavers** — Slow-motion video screensavers in `MacLock` that smoothly slow down and freeze into the desktop wallpaper upon unlock.
- [ ] **Finder Integration / Companion** — Deeper file-manager experience (column view, Finder tags, inspector, quick actions) or a dedicated macOS-style file browser.
