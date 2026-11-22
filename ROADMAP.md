# MacShell macOS Feature Parity Roadmap

This roadmap tracks features needed to bring **MacShell** (Hyprland + Quickshell) closer to full feature parity with modern **macOS (Sequoia / Tahoe)**.

Items are grouped by area. Each item includes a brief note on the current state in the codebase to make picking up any task straightforward.

---

## Quick Wins (Partially Implemented)

- [ ] **Expose remaining `ExtraWidgets.qml` widgets** — `batteries`, `notes`, `photos`, `alarms`, and `stocks` are already implemented in `MacShell/ExtraWidgets.qml`, but only `reminders` is exposed in `MacShell/MacWidgets.qml` (`typeNames`) and Settings.
- [ ] **Wire built-in `WindowDecor.qml` & `MinimizeFx.qml` into `shell.qml`** — Both components exist in `MacShell/` (traffic-light titlebars and the native Genie minimize shader) but are not instantiated in `MacShell/shell.qml` yet (currently Genie requires the external `contrib/genie` + `hyprglass` setup).
- [ ] **Render D-Bus notification action buttons & inline reply** — `MacShell/MacBar.qml` advertises `actionsSupported: true` on `NotificationServer`, but currently only invokes the `"default"` action on card click; named action buttons (Reply, Mark as Read, Snooze, etc.) are not rendered.
- [ ] **Search System Settings panes in Spotlight** — Reuse the Settings pane index (`keys` metadata in `MacShell/MacDock.qml`) so typing e.g. `night shift`, `bluetooth`, or `wallpaper` in Spotlight jumps straight to that pane.

---

## 1. Window Management & Multitasking

- [ ] **Mission Control** — Overview of all open windows across workspaces plus a top Spaces bar with live workspace thumbnails, drag-and-drop of windows between workspaces, and creating/closing workspaces.
- [ ] **App Exposé** — Spread out all open windows of a single application (triggered via shortcut or Dock interaction).
- [ ] **Stage Manager** — Optional left-edge strip of grouped app stages with live thumbnails to switch between window sets.
- [ ] **macOS Window Tiling & Snap-to-Edges** — Dragging windows to screen edges/corners to snap into halves/quarters, a hover tile menu on the green traffic-light button, and *Window → Move & Resize* layout presets.
- [ ] **Hot Corners (Active Screen Corners)** — Configurable actions per corner (Mission Control, Show Desktop, Lock Screen, Notification Center, Quick Note, Start Screen Saver).
- [ ] **Click Wallpaper to Reveal Desktop** — Clicking empty desktop space pushes all open windows to the screen edges and restores them on the next click.

---

## 2. Menu Bar & Control Center

- [ ] **Real Global Menu (`DBusMenu`)** — Replace or augment the hardcoded per-category menus (`File / Edit / View / Window / Help` in `MacShell/MacBar.qml`) with real application menu trees via `com.canonical.AppMenu.Registrar` / `DBusMenu`, including a searchable *Help* menu.
- [ ] **Auto-hide Menu Bar** — Option to hide the menu bar (globally or in fullscreen) and slide it in when the pointer hits the top screen edge.
- [ ] **Reorder & Hide Menu Bar Items** — Hold modifier + drag to reorder or hide status/tray icons directly on the bar.
- [ ] **Live Activities in Menu Bar** — macOS Tahoe–style compact status pills in the menu bar for ongoing activities (active timers from `ClockApp`, calls, recordings, background progress).
- [ ] **Real Focus Modes** — Expand *Settings → Focus* (`MacShell/MacDock.qml`, currently only Do Not Disturb + Keep Awake) into customizable Focus profiles (Work, Sleep, Personal, Gaming) with schedules, per-app notification allowlists, and optional per-Focus wallpapers.
- [ ] **Additional Control Center Modules** — Add missing tiles/sliders to `ccCatalog` in `MacShell/MacBar.qml`: Keyboard Brightness slider, Screen Mirroring / Display Casting, and AirDrop / Nearby Share toggle.

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
