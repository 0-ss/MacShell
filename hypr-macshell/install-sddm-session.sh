#!/bin/sh
# Installs the "Hyprland (MacShell)" SDDM login option. Run with sudo.
set -e
cat > /usr/local/bin/start-hyprland-macshell <<'W'
#!/bin/sh
# Hyprland + MacShell (github.com/0-ss/Macshell) with its own config tree,
# so the main ii session's ~/.config/hypr is never touched. See ~/.config/hypr-macshell/.
exec /usr/bin/start-hyprland -- --config "$HOME/.config/hypr-macshell/hyprland.lua"
W
chmod 755 /usr/local/bin/start-hyprland-macshell
cat > /usr/share/wayland-sessions/hyprland-macshell.desktop <<'E'
[Desktop Entry]
Name=Hyprland (MacShell)
Comment=macOS Tahoe-style MacShell on Hyprland (separate hypr config)
Exec=/usr/local/bin/start-hyprland-macshell
TryExec=/usr/local/bin/start-hyprland-macshell
Type=Application
E
command -v pacman >/dev/null 2>&1 && pacman -S --needed --noconfirm inter-font || true
echo "done: Hyprland (MacShell) is now on the SDDM session list"
