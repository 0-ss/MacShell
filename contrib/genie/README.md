# Genie minimize (optional)

Minimize a window into its own Dock icon with a magic-lamp animation, and bring it back from the Dock.
Nothing changes in MacShell until you install the helper below.

How it fits together:

* **hyprglass** (Hyprland plugin, BSD-3, <https://github.com/shlok-shinde/hyprglass>) draws the animation: `hyprctl hyprglass minimize|restore`.
* **`macshell-genie`** (this folder) is the helper. It remembers where each window was, aims the animation at the
  app's Dock icon, and parks the minimized window off-screen so it does not eat clicks.
* **The Dock** (`MacDock.qml`) notices the helper: it writes the icon positions to `~/.cache/macshell-dock-rects.json`
  and sends Dock clicks through the helper. Hyprland ignores `activate()` for a window on the hidden
  `special:minimized` workspace, which is why a plain Dock click could not bring such a window back.

Install:

```sh
git clone https://github.com/shlok-shinde/hyprglass && cd hyprglass && make     # needs the headers of your Hyprland
install -D build/hyprglass.so ~/.local/lib/hyprglass.so                          # adjust to where make puts the .so
install -Dm755 contrib/genie/macshell-genie ~/.local/bin/macshell-genie
install -D contrib/genie/genie.lua ~/.config/hypr/genie.lua
echo 'dofile(os.getenv("HOME") .. "/.config/hypr/genie.lua")' >> ~/.config/hypr/hyprland.lua
```

Restart MacShell. `Super+M` minimizes the active window, `Super+Shift+M` restores the last one, clicking the app in the
Dock restores it too. Remove `~/.local/bin/macshell-genie` and everything is back to normal.

Tested on Hyprland 0.56 (Lua config) with hyprglass 0.10.0. The window's own title bar (e.g. a hyprbars plugin) does
not bend with the genie, hide it while the animation runs if you use one.
