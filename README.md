# MacShell

A macOS Tahoe–style **menu bar + Dock** for Hyprland, built on [Quickshell](https://quickshell.org), with a real-time
"Liquid Glass" refraction shader, window previews, Spotlight, clipboard/emoji picker, notifications, Control Center,
screenshots, screen recording, desktop widgets (weather, calendar, clock, music player), a wallpaper picker and an
Alt+Tab switcher — all in one Quickshell process.

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/600f75bc-b4d1-442d-bec5-41ee7dfa5023" />

The repository also ships **MacLock**, a matching Liquid Glass lock screen. It is a separate Quickshell config on
purpose: it runs as its own process, so a shell crash can never take the lock with it.

Best Icon Pack for the shell is here : https://github.com/Scrimas/MacOS-Like

> **Heads up:** this targets **Hyprland 0.55+ with a Lua config** (`hyprland.lua`) and a recent **Quickshell (0.3.x)**.
> See [Requirements](#requirements) and [Known issues](#known-issues).

## Files

```
MacShell/               (this repository)
├── install.sh          installer / updater
├── README.md
├── MacShell/           the shell      ->  ~/.config/quickshell/MacShell
└── MacLock/            the lock screen ->  ~/.config/quickshell/MacLock
```

The two are installed as **separate** Quickshell configs (neither lives inside the other).

**MacShell**

| File | Purpose |
|---|---|
| `shell.qml` | Entry point. Shared hub: window geometry, wallpaper lookup, capture gating. |
| `MacBar.qml` | Menu bar, Control Center, Spotlight, notifications, switcher, screenshots, wallpaper picker. |
| `MacDock.qml` | Dock, window previews, and the Settings window. |
| `MacWidgets.qml` | Desktop widgets layer (hosts the widgets below). |
| `WeatherWidget.qml`, `WeatherIcon.qml`, `CalendarWidget.qml`, `ClockWidget.qml`, `PlayerWidget.qml`, `MarqueeText.qml` | The widgets and their helpers. |
| `liquidglass.frag` | Liquid Glass fragment shader (compiled to `.qsb` on first run). |
| `EmojiData.js` | Emoji fallback data for Spotlight (from [gemoji](https://github.com/github/gemoji), MIT). |
| `macshell-update` | Update tool (installed to `~/.local/bin`, see [Updating](#updating)). |
| `apple-logo-black.svg`, `apple-logo-white.svg` | Menu bar logo. |

**MacLock**

| File | Purpose |
|---|---|
| `shell.qml` | Entry point: session lock, IPC (`lockscreen`), preview mode. |
| `LockScreen.qml` | The lock screen UI and PAM password check. |
| `lock-via-ipc.sh` | Helper for your keybind: starts MacLock if needed, then locks. |
| `Glass.qml`, `Glyph.qml`, `MorphGlyph.qml`, `MorphText.qml`, `ClockGlyph.qml`, `ContourGlow.qml` and the `*.frag` / `*.qsb` shaders | Visuals. |
| `hyprland.lua` | Snippet with the keybind (copy it into your config). |

## Requirements

### Required

| What | Why |
|---|---|
| **Hyprland ≥ 0.55, running a Lua config** (`~/.config/hypr/hyprland.lua`) | Window actions, the Alt+Tab focus, "paste after picking" and Log Out use Lua dispatches (`hyprctl dispatch 'hl.dsp…'`, `hyprctl eval`). On older versions or a `.conf` session these actions fail; the bar, Dock, glass and previews still work. Quick test: `hyprctl dispatch 'hl.dsp.no_op()'` must not error. |
| **Quickshell ≥ 0.3.0** (0.3.2 recommended) | Needs the Hyprland module (`HyprlandToplevel`, `lastIpcObject`, Lua-config support), `ScreencopyView`, `IpcHandler`, and the UPower / Pipewire / Mpris / SystemTray / Notifications services. |
| Quickshell built with **Wayland**, **Hyprland**, **Screencopy → Hyprland Toplevel Export**, **Pipewire**, **UPower**, **Mpris**, **System Tray** | Distro packages normally enable all of these. Check the build info that `qs` prints in its logs. |
| **Qt 6.5+** with `qt6-declarative`, `qt6-wayland`, **`qt6-shadertools`** (provides `qsb`) | `QtQuick.Effects` (MultiEffect) needs 6.5+. `qsb` compiles `liquidglass.frag` on first run. Without it (and without a prebuilt `liquidglass.frag.qsb`) the glass falls back to "Normal Blur". |
| `qt6-svg` (recommended) | SVG app icons. |
| `hyprctl`, `sh`, `xdg-open` | Core. |
| An **icon theme** (Papirus, Adwaita, …) set for Qt apps | App icons in the Dock and Spotlight come from the system theme. If icons are blank, set one with `qt6ct` or `QS_ICON_THEME`. |
| `curl`, `tar` | Used by the installer and the updater. |
| Font **Inter** (default) | Falls back to the system font; "Noto Sans" / "System" can be chosen in Settings. |

### MacLock (only if you use the lock screen)

| What | Why |
|---|---|
| A PAM stack at `/etc/pam.d/hyprlock` (installed by the `hyprlock` package) | MacLock checks passwords with it. The installer warns if the file is missing. |
| Quickshell with the **Pam** and **session-lock** modules | Distro packages normally include them. |
| Hyprland `misc:allow_session_lock_restore` (recommended) | Lets a restarted MacLock take over a lock if it ever dies. |

### Optional (missing tools just disable that feature)

| Feature | Tool(s) |
|---|---|
| Screenshots (Print key) | `grim`, `wl-clipboard` (clipboard copy), `libnotify` (`notify-send`) |
| Clipboard history + Emoji (Spotlight) | `wl-clipboard`, `cliphist` (the shell starts the `wl-paste --watch cliphist store` watchers itself) |
| Screen recording | `wf-recorder` |
| Color picker | `hyprpicker` |
| Night Shift | `hyprsunset` |
| Brightness | `brightnessctl` |
| Wi-Fi / VPN / Ethernet | NetworkManager (`nmcli`); fallback editor `nm-connection-editor` or `nmtui` |
| Bluetooth | `bluez` (`bluetoothctl`) |
| Audio device routing | `wpctl` (WirePlumber) or `pactl` |
| Privacy indicators | PipeWire (`pw-dump`) |
| Keep Awake | `systemd-inhibit` |
| Lock / Sleep / Restart / Shut Down | `loginctl`, `systemctl` (UWSM sessions are stopped via `uwsm`) |
| Trash watching / emptying | `inotify-tools` (`inotifywait`), `ktrash6`/`ktrash5`, or a file manager (`dolphin`, `nautilus`, `thunar`, `nemo`, `pcmanfm-qt`) |
| Folder pickers in Settings | `zenity`, `kdialog` or `yad` |
| "About This Linux" | `fastfetch` or `neofetch` |
| Do Not Disturb (Focus) | `dunstctl`, `makoctl` or `swaync-client` (only if you keep one of those) |
| Emoji search keywords | `emoji-test.txt` from the `unicode-emoji` package (otherwise `EmojiData.js` is used) |
| Wallpaper detection / applying | one of: Noctalia, `awww`/`swww`, `hyprpaper`, `swaybg`, `wpaperd` — or set a path yourself (see [Wallpaper](#wallpaper)) |
| Installer extras | `rsync` (faster file sync), `systemd` (daily automatic updates) |
| Default apps | terminal `kitty`, file opener `xdg-open` — change `terminal`, `launcher`, `filesCmd`, `clipboardCmd` in `~/.config/macbar/settings.json` |

### Conflicts

This shell **replaces** your bar, dock and notification daemon. Stop anything that overlaps:

- Other bars/shells (waybar, hyprpanel, ags, Noctalia, Caelestia, …) and docks (nwg-dock, …).
- Notification daemons (`dunst`, `mako`, `swaync`): the bar owns `org.freedesktop.Notifications`.
  `systemctl --user disable --now dunst` (or `mako` / `swaync`).

## Install

1. Install the requirements above. On Arch, for example:
   ```sh
   sudo pacman -S hyprland quickshell qt6-declarative qt6-wayland qt6-shadertools qt6-svg hyprlock \
        grim wl-clipboard wf-recorder cliphist libnotify brightnessctl networkmanager bluez-utils inotify-tools \
        ttf-inter noto-fonts-emoji
   ```
   Other distros: install the equivalents. Fedora has a Quickshell COPR; Nix has `pkgs.quickshell`.
   You can skip this: the installer checks every requirement (tools, Qt libraries, fonts, `hyprlock`) and installs
   the missing ones for you with pacman, dnf or apt, after asking once (`-y` skips the question). Packages that are
   not in the main repositories, such as `quickshell`, come from the AUR (`yay` / `paru`) or the Fedora COPR.
   Hyprland 0.55+ with a Lua config may need a newer package than your distro ships, so check `hyprctl version`.
   Debian/Ubuntu have no `quickshell` / `hyprland` packages: build those from source.
2. Run the installer, either from a clone:
   ```sh
   git clone https://github.com/0-ss/MacShell
   cd MacShell
   bash install.sh
   ```
   or in one line:
   ```sh
   curl -fsSL https://raw.githubusercontent.com/0-ss/MacShell/main/install.sh | bash
   ```
   It installs **MacShell** to `~/.config/quickshell/MacShell` and **MacLock** to `~/.config/quickshell/MacLock`,
   and can add the autostart line to your Hyprland config. Your settings are never touched, and the previous
   install is backed up first (last 3 kept in `~/.local/share/macshell/backups/`).

   When run from a clone, the installer first checks GitHub: if the repository has a newer version (and your clone has
   no uncommitted changes) it downloads and installs that one automatically.

   Don't reach the install folders through a symlink; Quickshell ≥ 0.3 derives its state folders from the link path.
3. Try it:
   ```sh
   qs -c MacShell
   ```
   On first run with the Liquid Glass style, `liquidglass.frag` is compiled with `qsb` and cached in
   `~/.config/macdock/liquidglass.frag.qsb`. Watch for `[macbar-glass] state: ready` in the log.
4. Add the Hyprland config below, then autostart it.

### Installer options

| Option | Effect |
|---|---|
| `-y`, `--yes` | Don't ask questions (answer yes). |
| `--no-deps` | Skip the dependency check and package installation. |
| `--no-autostart` | Don't touch the Hyprland config. |
| `--no-lock` | Install MacShell only, without MacLock. |
| `--check` | Only check for a newer version (exit 0 = up to date, 10 = update available). |
| `--local` | Install the local clone as it is, don't look for a newer version on GitHub. |
| `--auto-update` / `--no-auto-update` | Set up / remove a daily systemd user timer that installs updates by itself. |
| `--ref REF` | Install a specific tag or commit. |
| `--from-dir DIR` | Install from a local folder instead of downloading. |
| `--uninstall` | Remove MacShell and MacLock (settings are kept). |

Environment: `MACSHELL_REPO`, `MACSHELL_BRANCH`, `MACSHELL_DEST`, `MACLOCK_DEST`, `GITHUB_TOKEN`.

## Updating

```sh
macshell-update check       # is there a newer version?
macshell-update update      # download and install it (MacShell and MacLock)
macshell-update rollback    # go back to the previous MacShell install
macshell-update status
```

The shell also checks by itself and tells you. `bash install.sh --check` does the same check from a clone, and
`bash install.sh --auto-update` installs a daily timer (`systemctl --user list-timers macshell-update.timer`) so updates
install without you doing anything. MacShell reloads itself after an update; MacLock picks up the new files the next
time it locks.

## Hyprland configuration (Lua)

```lua
-- autostart (remove other bars / docks / notification daemons first)
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -c MacShell")
end)

-- layer rules: blur for the glass surfaces
hl.layer_rule({ name = "macdock",  match = { namespace = "macdock"  }, blur = true, ignore_alpha = 0.2,  no_anim = true })
hl.layer_rule({ name = "macspot",  match = { namespace = "macspot"  }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ name = "macbarbg", match = { namespace = "macbarbg" }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ name = "macshot",  match = { namespace = "macshot"  }, no_anim = true })   -- optional: no fade on the screenshot picker

-- Settings window (fixed size). Hyprland usually floats it on its own; if it tiles, add a float rule for the title
-- "macshell Settings" (see /usr/share/hypr/hyprland.lua for the window_rule syntax of your version).

-- keybinds (the name after -c is the config folder name, case-sensitive)
local qs = "qs -c MacShell ipc call "

hl.bind("SUPER + V",          hl.dsp.exec_cmd(qs .. "spotlight clipboard"))
hl.bind("SUPER + period",     hl.dsp.exec_cmd(qs .. "spotlight emoji"))
hl.bind("SUPER + Space",      hl.dsp.exec_cmd(qs .. "spotlight toggle"))
hl.bind("ALT + TAB",          hl.dsp.exec_cmd(qs .. "switcher next"))
hl.bind("CTRL + ALT + W",     hl.dsp.exec_cmd(qs .. "wallpapers toggle"))
hl.bind("PRINT",              hl.dsp.exec_cmd(qs .. "screenshot region"))

-- MacLock (lock screen)
hl.bind("SUPER + L",          hl.dsp.exec_cmd("sh ~/.config/quickshell/MacLock/lock-via-ipc.sh"))
```

Change `SUPER + L` if that key is already used. On a classic `hyprland.conf` the same bind is
`bind = SUPER, L, exec, sh ~/.config/quickshell/MacLock/lock-via-ipc.sh`.

Also make sure **blur is enabled** in your Hyprland `decoration` settings, or the "Normal Blur" style won't blur.

### IPC reference

`qs -c MacShell ipc call <target> <function>`

| Target | Functions |
|---|---|
| `spotlight` | `toggle`, `clipboard`, `emoji`, `apps` |
| `screenshot` | `region`, `screen`, `window` |
| `wallpapers` | `toggle`, `open`, `close` |
| `switcher` | `next`, `prev`, `commit`, `cancel` |
| `settings` | `open` (works even if both the bar and the Dock are disabled) |
| `widgets` | `refresh` (re-fetch the weather), `edit true\|false` (move / resize desktop widgets) |
| `glass` | `captures true\|false` (window previews on/off, same as Settings → Dock Behavior → *Live window capture*) |

## MacLock

A macOS-style lock screen using the same Liquid Glass look. Each lock runs in its own process (a Wayland session lock
is used once), and `lock-via-ipc.sh` starts a fresh one for every lock, so the keybind above is all you need.

```sh
sh ~/.config/quickshell/MacLock/lock-via-ipc.sh        # lock now (what the keybind runs)
qs -c MacLock ipc call lockscreen lock                 # same, if an IPC-ready MacLock is already running
qs -c MacLock                                          # lock immediately, one-shot (e.g. from hypridle)
MACLOCK_PREVIEW=1 qs -c MacLock                        # preview the design as a window, no real lock
```

Passwords are checked with PAM (`/etc/pam.d/hyprlock`). To lock on idle or before sleep with `hypridle`, set
`lock_cmd = sh ~/.config/quickshell/MacLock/lock-via-ipc.sh`.

## Wallpaper

The Liquid Glass refracts your wallpaper, so the shell needs its file path. It looks, in order, at: the `wallpaperPath`
override in `settings.json`, Noctalia's `settings.toml`, `awww`/`swww query`, `hyprctl hyprpaper listactive`, and
`~/.config/hypr/hyprpaper.conf`. If yours isn't detected (swaybg, wpaperd, a custom script), either pick a wallpaper in the
built-in picker (Ctrl+Alt+W; it remembers the path), or set `"wallpaperPath": "/path/to/image.png"` in
`~/.config/macdock/settings.json`. The picker reads `~/Pictures/Wallpapers` by default (`wallpaperDir`).

## Where things are stored

| Path | Content |
|---|---|
| `~/.config/macbar/settings.json` | Menu bar settings |
| `~/.config/macdock/settings.json`, `pinned.json` | Dock settings and pinned apps |
| `~/.config/macdock/liquidglass.frag.qsb` | Compiled shader cache |
| `~/.config/macwidgets/settings.json` | Desktop widgets and their placement |
| `~/.local/share/macshell/` | Installer state, `macshell-update`, backups |
| `~/.cache/macbar/` | Clipboard history helper files (images, timestamps) |
| `~/Pictures/Screenshots` | Default screenshot folder |

Clipboard history is kept on disk (cliphist's database plus `~/.cache/macbar/clip`). Turn it off with `clipHistory: false`
in `~/.config/macbar/settings.json` if you don't want that.

## Troubleshooting

| Symptom | Check |
|---|---|
| Glass looks flat / "Normal Blur" | `qsb` missing (install `qt6-shadertools`) — the log shows `[macbar-glass] state: failed`. Or ship a prebuilt `liquidglass.frag.qsb` next to `liquidglass.frag`; it is used as a fallback. |
| Glass shows no wallpaper | Wallpaper not detected: see [Wallpaper](#wallpaper). |
| Blank app icons | No Qt icon theme: set one (`qt6ct`, or `QS_ICON_THEME`) and install it. |
| No notifications | Another daemon owns the D-Bus name. Disable it and restart the shell. |
| Window menu actions, Alt+Tab focus, paste-after-pick or Log Out do nothing | Not on a Lua-config Hyprland 0.55+: run `hyprctl dispatch 'hl.dsp.no_op()'`. |
| No window previews / glass behind windows | Quickshell built without Hyprland Toplevel Export, or Settings → Dock Behavior → *Live window capture* is off. |
| Log | `qs log` (see `qs --help` for selecting the config). |

## Known issues

**Shell crash with `wl_display#1: error 0: invalid object NNN`** when many windows open/close quickly (a game launching,
spamming terminals) while live window capture runs. A window closes while a capture frame for it is still pending; Hyprland
does not answer that frame, the shell then destroys it, and the compositor drops the Wayland connection. Mitigations:

- Settings → Menu Bar → turn **Real-time glass** off (far fewer captures; the biggest win).
- Settings → Dock Behavior → turn **Live window capture** off.
- The shell already pauses glass captures while windows open/close.
- Auto-restart it: `sh -c 'while :; do qs -c MacShell; sleep 1; done'` as the autostart command.

Glitchy window capture,
Can be disabled in Settings:

- Settings → Dock Behavior → turn **Live window capture** off.

Reproduced on Hyprland 0.56.2 / Quickshell 0.3.2

## Credits

Emoji data from [GitHub gemoji](https://github.com/github/gemoji) (MIT).
