# MacShell on Debian 13 (trixie)

MacShell is developed on Arch. This page covers what differs on Debian-based systems, and what the installer now does about it.

**Tested on:** Debian 13 "trixie" with `trixie-backports`, Hyprland 0.55.2, Quickshell 0.3.0, Qt 6.8.2, GDM, an Intel Iris Plus laptop (i3-1005G1, 1366x768). MacShell and MacLock load with no QML errors and the flat (`blur`) bar style has been used day to day.
**Not verified:** the visual quality of the Liquid Glass style on Qt 6.8 (it loads without errors, nothing more is claimed), other Debian releases, and Ubuntu.

## 1. Hyprland and Quickshell come from backports

Neither is in Debian 13's main repository. Enable `trixie-backports` and install both from there:

```sh
echo 'deb http://deb.debian.org/debian trixie-backports main' | sudo tee /etc/apt/sources.list.d/backports.list
sudo apt update
sudo apt install -t trixie-backports hyprland quickshell hyprlock hyprland-guiutils xwayland
```

`hyprland-guiutils` silences the "install hyprland-guiutils" notice at startup. Hyprland 0.55+ uses a Lua config (`~/.config/hypr/hyprland.lua`), as the main README describes.

## 2. Install

```sh
git clone https://github.com/0-ss/MacShell && cd MacShell
bash install.sh
```

On `apt` systems the installer now also installs the Qt QML modules and plugins MacShell imports (Debian splits Qt into many packages: `qml6-module-qtquick*`, `qml6-module-qtmultimedia`, `qt6-wayland`, `qt6-svg-plugins`, ...). Without them Quickshell fails with "module not installed".

## 3. Compatibility fixes the installer applies

| Problem on Debian 13 | What the installer does |
|---|---|
| `RectangularShadow is not a type` (it only exists in Qt >= 6.9; Debian 13 ships 6.8) | Detects the Qt version and, if older than 6.9 (or unknown), copies `compat/qt-6.8/RectangularShadow.qml` into MacShell and MacLock. It is built from stacked translucent rounded rectangles (no shaders), so it looks a little different from the real one. |
| The "Inter Variable" font is requested but Debian only packages static "Inter" | Writes `~/.config/fontconfig/conf.d/60-macshell-inter.conf`, an alias from "Inter Variable" to "Inter". Without it the text falls back to DejaVu Sans. |

Both steps run after the files are copied, so they also survive `macshell-update`.

## 4. Hyprland session tips

- **`PATH` and `XDG_DATA_DIRS`.** A session started from a display manager can lack `/usr/games`, `~/.local/bin`, and the Flatpak and Snap data directories. Symptoms: commands missing in terminals opened from MacShell, and Flatpak/Snap apps absent from Spotlight and the app library. Set them in `hyprland.lua` (use your real home path):
  ```lua
  hl.env("PATH", "/home/YOU/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:/snap/bin")
  hl.env("XDG_DATA_DIRS", "/home/YOU/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share:/var/lib/snapd/desktop")
  ```
- **MacLock** checks passwords against `/etc/pam.d/hyprlock`, which comes from the `hyprlock` package (also in trixie-backports).
- **Touchpad.** Hyprland's defaults differ from GNOME's. For two-finger right click and tap-and-drag, add to `input.touchpad`: `clickfinger_behavior = true`, `tap_and_drag = true`, `tap_to_click = true`. In the Lua config the keys use underscores (`tap_to_click`, not `tap-to-click`).
- **Agents you lose when leaving GNOME:** start a polkit agent (`hyprpolkitagent`) and, if you rely on stored passwords, `gnome-keyring-daemon --start --components=secrets,pkcs11`.

## 5. Known limitations

- Settings -> *Install dependencies* targets Arch. `awww` and `mpvpaper` are not in the Debian repositories, so animated wallpaper transitions and video wallpapers are unavailable; wallpapers are applied through `hyprpaper`, which MacShell detects on its own. `quickshell`, `ffmpeg` and `wf-recorder` do come from apt.
- Do not run a bare `rsync --delete` over the installed folders by hand: the shim above lives next to MacShell's own files and is re-created by `install.sh`.
