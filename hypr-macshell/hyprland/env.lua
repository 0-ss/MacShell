local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
hl.env("XDG_DATA_DIRS", home_dir .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share:" .. xdg_data_dirs_old)

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")

-- Private upstream Quickshell for illogical-impulse
-- noctalia-qs (the Noctalia fork) owns /usr/bin/qs but ii is developed against
-- upstream quickshell-git (see dots-hyprland install-deps.sh). Use the private
-- upstream Quickshell under ~/.local/opt, same as the Caelestia session, so the
-- Noctalia session keeps its fork untouched.
local qs_prefix = home_dir .. "/.local/opt/quickshell-upstream"
local qs_bin = qs_prefix .. "/usr/bin"
local qs_qml = qs_prefix .. "/usr/lib/qt6/qml"
-- only when that private build exists (otherwise the system's quickshell is used)
if is_file_exists(qs_bin .. "/quickshell") then
    local cur_path = os.getenv("PATH") or ""
    if not cur_path:find(qs_bin, 1, true) then
        hl.env("PATH", qs_bin .. ":" .. cur_path)
    end
    hl.env("QML2_IMPORT_PATH", qs_qml)
    hl.env("QML_IMPORT_PATH", qs_qml)
end
