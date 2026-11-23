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

- [ ] **Dock Folders / Stacks** — Pin folders (e.g. Downloads, Documents) next to Trash with macOS-style Fan, Grid, and List popovers.
- [ ] **Left & Right Dock Positioning** — Support vertical Dock orientation on the left or right screen edge, including magnification and glass layout.
- [ ] **Notification Badges** — Show red unread badge counters on Dock app icons (e.g. via Unity/LauncherEntry D-Bus or unread notification counts).
- [ ] **Recent Apps Section** — Optional section between pinned apps and Trash showing the last N recently closed applications.
- [ ] **Drag & Drop Files onto Dock App Icons** — Allow dropping files from the desktop (or file managers) onto any Dock app icon to open them with that app (currently only Trash accepts desktop drops).

---

## 4. Spotlight (macOS Tahoe Parity)

- [ ] **Full-Text & Metadata File Search** — Upgrade file search (`find -iname` in `MacShell/MacBar.qml`) to support indexed content/metadata search (e.g. local FTS index, Recoll/Tracker/ripgrep integration) for documents, PDFs, and notes.
- [ ] **Quick Look Preview Pane** — Split-view preview panel on the right side of Spotlight results for files, images, screenshots, and documents.
- [ ] **Spotlight Actions & Quick Keys** — Expand the *Actions* tab beyond the 6 power/system commands to support app actions, user-defined shortcuts/scripts, quick keys, and direct creation of timers, reminders, and notes.
- [ ] **Inline Knowledge Cards** — Live currency conversion, dictionary definitions, and inline weather/stock summary cards directly in Spotlight results.

---

## 5. Notifications, Widgets & Desktop

- [ ] **Grouped / Stacked Notifications** — Collapse multiple notifications from the same app into an expandable stack in Notification Center.
- [ ] **Combined Notification Center + Widgets Sidebar** — Clicking the clock (or swiping from the right edge) opens a unified right-hand panel showing notifications alongside widgets, rather than only the calendar popover.
- [ ] **Multi-Monitor Desktop Widgets** — Lift the primary-monitor-only limitation in `MacShell/MacWidgets.qml` so widgets can be placed on any connected display.
- [ ] **Desktop Stacks** — Automatically group desktop files into expandable stacks by file type, date, or tag in `MacShell/Desktop.qml`.
- [ ] **System-Wide Quick Look (`Space`)** — Instant floating Liquid Glass preview for images, PDFs, video, audio, and code/markdown files triggered via `Space` (beyond the current desktop right-click image/info preview).

---

## 6. Screenshots, System Dialogs & Settings

- [ ] **Floating Screenshot Thumbnail** — Show a draggable preview thumbnail in the bottom-right corner after capturing, with click-to-edit and auto-dismiss.
- [ ] **Built-in Markup / Annotation Editor** — Quick annotation tools (arrows, shapes, text, blur/redact, crop) directly on captured screenshots.
- [ ] **Capture Toolbar (`Cmd+Shift+5` style)** — Unified on-screen bar to switch between region/window/screen screenshot and screen recording, plus timer delay, mic/system audio toggle, and destination picker.
- [ ] **Liquid Glass Polkit Auth Agent** — Native macOS-style authentication prompt supporting password and fingerprint (`fprintd`).
- [ ] **Force Quit Dialog & Native Activity Monitor** — Dedicated `Cmd+Opt+Esc` Force Quit window and a built-in Liquid Glass Activity Monitor (currently the button in `MacShell/MacBar.qml` launches external tools like `gnome-system-monitor` or `btop`).
- [ ] **Missing System Settings Panes**:
  - [ ] **Storage** — Color-coded disk usage breakdown bar and cleanup helpers.
  - [ ] **Privacy & Security** — App permissions (camera/mic/screen portals) and firewall controls.
  - [ ] **Accessibility** — Screen zoom, color filters, cursor size/shake-to-find (currently only Reduce Motion).
  - [ ] **Login Items / Autostart** — Manage XDG autostart entries and background services.
  - [ ] **Date & Time** — Timezone picker, NTP toggle, and date format options.
  - [ ] **Printers & Scanners** — CUPS printer status and queue management.
  - [ ] **Sharing** — Toggles for SSH, SMB/Samba, and screen sharing.
  - [ ] **System Software Update** — Unified distro package update checker alongside MacShell's own updater.

---

## 7. Ecosystem & Linux Integrations

- [ ] **AirDrop / Continuity / Phone Mirroring** — Integrate KDE Connect / GSConnect, LocalSend, and `scrcpy` into the Control Center, share menus, and notifications for file drops, universal clipboard, and phone mirroring.
- [ ] **Time Machine UI** — Visual snapshot browser and file restore interface backed by Btrfs + Snapper (or Timeshift).
- [ ] **Aerial Screensavers** — Slow-motion video screensavers in `MacLock` that smoothly slow down and freeze into the desktop wallpaper upon unlock.
- [ ] **Finder Integration / Companion** — Deeper file-manager experience (column view, Finder tags, inspector, quick actions) or a dedicated macOS-style file browser.
