#!/usr/bin/env bash
# MacShell installer / updater
#
#   curl -fsSL https://raw.githubusercontent.com/0-ss/MacShell/main/install.sh | bash
#   ./install.sh            (from a clone of the repository)
#
# What it does
#   1. checks every tool, library, font and service MacShell / MacLock need and installs the missing ones
#      (pacman, dnf or apt; packages the main repositories lack come from the AUR / the Fedora COPR, and on Arch it can
#      even set up an AUR helper for you). It also enables the bluetooth service, which Bluetooth needs.
#   2. downloads the latest release (or the latest commit of the main branch)
#   3. installs the shell to   ~/.config/quickshell/MacShell        (start it with:  qs -c MacShell)
#      the lock screen to      ~/.config/quickshell/MacLock         (lock with:  sh ~/.config/quickshell/MacLock/lock-via-ipc.sh)
#      (MacShell and MacLock are two separate Quickshell configs; neither is placed inside the other)
#      the helper tree to      ~/.config/hypr-macshell              (scripts/ = Game Mode, video wallpapers, AirDrop, lock helper;
#                                                                   plus the standalone Hyprland session config, hypridle / hyprlock files;
#                                                                   your own custom/ folder is never overwritten)
#      app launchers to        ~/.local/share/applications          (Finder, Photos, Clock ... entries for macshell-*.desktop)
#      icons to                ~/.local/share/icons/hicolor/scalable/apps
#      the Apple emoji font rule to ~/.config/fontconfig/conf.d
#      sounds to               ~/.local/share/sounds/macshell       (shipped ones, plus the rest synthesized by macshell-make-sounds.py)
#      the update tool to      ~/.local/share/macshell/bin/macshell-update  (+ ~/.local/bin/macshell-update)
#      the start script to     ~/.local/share/macshell/bin/macshell-start   (+ ~/.local/bin/macshell-start)
#   4. installs ~/.config/hypr/macshell.lua with the autostart and keybinds, then loads it from hyprland.lua
#      (Hyprland 0.55+), or adds an exec-once line to hyprland.conf. It never writes to a config Hyprland is not using.
#   5. optionally sets up automatic updates (a daily systemd user timer)
#
# Updates
#   Run ./install.sh and pick from the menu: 1) install shell, 2) check for updates (asks whether to install one),
#   3) uninstall shell, 4) bind help (opens the Hyprland keybind section of the README).
#   An update installs the dependencies the new version needs, updates MacShell and MacLock together and keeps your
#   settings. Use --local to install exactly what is in a clone, or --check to only look.
#   (macshell-update still exists for the daily timer and for scripts; "macshell-update rollback" restores both.)
#
# Your settings (~/.config/macbar, macdock, macshell, macwidgets, ...) are never touched.
# Before replacing an existing install, the old one is saved to ~/.local/share/macshell/backups/ (last 3 kept).
#
# Options
#   -y, --yes             do not ask questions (answer yes)
#       --no-deps         skip the dependency check
#       --deps-only       only check / install dependencies, then stop
#       --no-services     do not enable system services (bluetooth, NetworkManager, power profiles, PipeWire)
#       --doctor          check the whole setup (environment, services, wallpaper, shaders, Hyprland) and explain problems
#       --low-power       settings for older computers (no live window capture, no magnification, plain blur)
#       --no-autostart    do not touch the Hyprland config
#       --no-rules        do not add the Liquid Glass layer rules to the Hyprland config
#       --channel CH      release (default: latest release, else the main branch) or main (always the newest commit)
#       --ref REF         install a specific tag / commit instead of the latest
#       --from-dir DIR    install from a local folder instead of downloading
#       --update          quiet update mode (used by macshell-update)
#       --uninstall       remove MacShell (settings are kept)
#       --no-lock         do not install MacLock
#       --check           only check whether a newer version exists (exit 0 = up to date, 10 = update available)
#       --local           install the local copy as it is, do not look for a newer version on GitHub
#       --auto-update     install a daily systemd user timer that updates MacShell + MacLock by itself
#       --no-auto-update  remove that timer
#   -h, --help
#
# Environment variables for the shell itself (icon theme, Qt platform, software rendering, ...) go in
#   ~/.config/macshell/env   (the installer creates it with comments; macshell-start reads it)
#
# Environment: MACSHELL_REPO (default 0-ss/MacShell), MACSHELL_BRANCH (default main), MACSHELL_CHANNEL, MACSHELL_DEST,
#              MACLOCK_DEST, GITHUB_TOKEN

set -euo pipefail

REPO="${MACSHELL_REPO:-0-ss/MacShell}"
BRANCH="${MACSHELL_BRANCH:-main}"
NAME="MacShell"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST="${MACSHELL_DEST:-$CONFIG_HOME/quickshell/$NAME}"
LOCK_NAME="MacLock"
LOCK_DEST="${MACLOCK_DEST:-$CONFIG_HOME/quickshell/$LOCK_NAME}"
STATE_DIR="$DATA_HOME/macshell"
BIN_DIR="$STATE_DIR/bin"
BACKUP_DIR="$STATE_DIR/backups"
HYPR_MAC_DIR="$CONFIG_HOME/hypr-macshell"
SCRIPTS_DIR="$HYPR_MAC_DIR/scripts"
APPS_DIR="$DATA_HOME/applications"
ICONS_DIR="$DATA_HOME/icons/hicolor/scalable/apps"
FONTCONF_DIR="$CONFIG_HOME/fontconfig/conf.d"
SOUNDS_DIR="$DATA_HOME/sounds/macshell"
LINK_DIR="$HOME/.local/bin"
HYPR_DIR="$CONFIG_HOME/hypr"
MARK_BEGIN="-- >>> MacShell (added by install.sh) >>>"
MARK_END="-- <<< MacShell <<<"
MACLUA_BEGIN="-- >>> MacShell module (added by install.sh) >>>"
MACLUA_END="-- <<< MacShell module <<<"
CONF_BEGIN="# >>> MacShell (added by install.sh) >>>"
CONF_END="# <<< MacShell <<<"

ENV_DIR="$CONFIG_HOME/macshell"
DOCTOR=0
LOW_POWER=0
MODE_FLAG=0       # a mode option was given (no menu)
ASSUME_YES=0
SKIP_DEPS=0
DEPS_ONLY=0
SKIP_SERVICES=0
SKIP_AUTOSTART=0
SKIP_RULES=0
SKIP_LOCK=0
CHECK_ONLY=0
LOCAL_ONLY=0
AUTO_UPDATE=""
BACKUP_TS=""
UPDATE_MODE=0
UNINSTALL=0
REF=""
FROM_DIR=""
CHANNEL="${MACSHELL_CHANNEL:-}"
RESOLVED_ID=""
RESOLVED_TYPE=""

# ───────────────────────── output helpers ─────────────────────────
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'; else B=""; G=""; Y=""; R=""; D=""; N=""; fi
say()  { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s%s%s\n' "$G" "$N" "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# confirm "question" [default y|n]
confirm() {
    local def="${2:-y}" ans="" hint="[Y/n]"
    [ "$def" = n ] && hint="[y/N]"
    [ "$ASSUME_YES" = 1 ] && return 0
    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        printf '%s %s ' "$1" "$hint" >/dev/tty
        read -r ans </dev/tty || ans=""
    else
        ans=""
    fi
    case "${ans:-$def}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

# ───────────────────────── arguments ─────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --no-deps) SKIP_DEPS=1 ;;
        --deps-only) DEPS_ONLY=1; MODE_FLAG=1 ;;
        --no-services) SKIP_SERVICES=1 ;;
        --doctor) DOCTOR=1; MODE_FLAG=1 ;;
        --low-power) LOW_POWER=1 ;;
        --no-autostart) SKIP_AUTOSTART=1 ;;
        --no-rules) SKIP_RULES=1 ;;
        --no-lock) SKIP_LOCK=1 ;;
        --check) CHECK_ONLY=1; SKIP_DEPS=1; MODE_FLAG=1 ;;
        --local) LOCAL_ONLY=1; MODE_FLAG=1 ;;
        --auto-update) AUTO_UPDATE=yes ;;
        --no-auto-update) AUTO_UPDATE=no ;;
        --update) UPDATE_MODE=1; SKIP_AUTOSTART=1; SKIP_SERVICES=1; ASSUME_YES=1; MODE_FLAG=1 ;;
        --uninstall) UNINSTALL=1; MODE_FLAG=1 ;;
        --channel) CHANNEL="${2:-}"; shift ;;
        --ref) REF="${2:-}"; MODE_FLAG=1; shift ;;
        --from-dir) FROM_DIR="${2:-}"; MODE_FLAG=1; shift ;;
        --resolved-id) RESOLVED_ID="${2:-}"; shift ;;
        --resolved-type) RESOLVED_TYPE="${2:-}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

state_get() { [ -f "$STATE_DIR/state.env" ] && sed -n "s/^$1=//p" "$STATE_DIR/state.env" | head -n1 || true; }
[ -n "$CHANNEL" ] || CHANNEL="$(state_get channel_pref)"
[ -n "$CHANNEL" ] || CHANNEL="release"
case "$CHANNEL" in release|main) ;; *) die "--channel must be 'release' or 'main'" ;; esac

[ "$(id -u)" -eq 0 ] && warn "running as root: MacShell is installed per user, run this as your normal user instead."

# ───────────────────────── automatic updates (systemd user timer) ─────────────────────────
UNIT_DIR="$CONFIG_HOME/systemd/user"

remove_auto_update() {
    have systemctl && systemctl --user disable --now macshell-update.timer >/dev/null 2>&1 || true
    rm -f "$UNIT_DIR/macshell-update.timer" "$UNIT_DIR/macshell-update.service"
    have systemctl && systemctl --user daemon-reload >/dev/null 2>&1 || true
    [ "${1:-}" = quiet ] || ok "automatic updates removed"
}

setup_auto_update() {
    if ! have systemctl || ! systemctl --user show-environment >/dev/null 2>&1; then
        warn "systemd user session not available: automatic updates were not set up (run 'macshell-update update' by hand)"
        return 0
    fi
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_DIR/macshell-update.service" <<UNIT
[Unit]
Description=Update MacShell and MacLock from GitHub
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$BIN_DIR/macshell-update update --yes --notify
UNIT
    cat > "$UNIT_DIR/macshell-update.timer" <<UNIT
[Unit]
Description=Check for MacShell updates daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
UNIT
    systemctl --user daemon-reload
    if systemctl --user enable --now macshell-update.timer >/dev/null 2>&1; then
        ok "automatic updates on (daily): systemctl --user list-timers macshell-update.timer"
    else
        warn "could not enable macshell-update.timer"
    fi
}

# ───────────────────────── uninstall ─────────────────────────
remove_hypr_blocks() {
    local f
    for f in "$HYPR_DIR/hyprland.lua"; do
        [ -f "$f" ] && grep -qF -- "$MARK_BEGIN" "$f" && { sed -i "\|$MARK_BEGIN|,\|$MARK_END|d" "$f"; ok "removed the MacShell block from $f"; }
    done
    f="$HYPR_DIR/macshell.lua"
    if [ -f "$f" ] && grep -qF -- "$MACLUA_BEGIN" "$f"; then
        if [ -f "$f.macshell-backup" ]; then mv -f "$f.macshell-backup" "$f"; else rm -f "$f"; fi
        ok "removed the generated MacShell module from $f"
    fi
    f="$HYPR_DIR/hyprland.conf"
    [ -f "$f" ] && grep -qF -- "$CONF_BEGIN" "$f" && { sed -i "\|$CONF_BEGIN|,\|$CONF_END|d" "$f"; ok "removed the MacShell block from $f"; }
    return 0
}

do_uninstall() {
    step "Uninstalling MacShell"
    if [ -d "$DEST" ]; then
        ts=$(date +%Y%m%d-%H%M%S); mkdir -p "$BACKUP_DIR/$ts"
        mv "$DEST" "$BACKUP_DIR/$ts/$NAME"; ok "moved $DEST to $BACKUP_DIR/$ts/"
    else
        warn "$DEST does not exist"
    fi
    if [ -d "$LOCK_DEST" ]; then
        ts=${ts:-$(date +%Y%m%d-%H%M%S)}; mkdir -p "$BACKUP_DIR/$ts"
        mv "$LOCK_DEST" "$BACKUP_DIR/$ts/$LOCK_NAME"; ok "moved $LOCK_DEST to $BACKUP_DIR/$ts/"
    fi
    remove_auto_update quiet
    remove_hypr_blocks
    rm -f "$LINK_DIR/macshell-update" "$LINK_DIR/macshell-start" "$BIN_DIR/macshell-update" "$BIN_DIR/macshell-start" "$STATE_DIR/state.env"
    ok "removed the update and start tools"
    say "Your settings were kept (~/.config/macbar, macdock, macshell, macwidgets). The helper tree stays in $HYPR_MAC_DIR (remove it by hand if you like)."
    say "If you added them yourself, remove the MacShell autostart and the MacLock lock keybind from your Hyprland config."
    exit 0
}
[ "$UNINSTALL" = 1 ] && do_uninstall

# ───────────────────────── dependencies ─────────────────────────
# command:arch-package:what-for   (a check by command name; package names are Arch names, translated per distro below)
REQUIRED=(
    "qs:quickshell:the shell runtime (needs the Hyprland, Screencopy, PipeWire, UPower, Mpris and Notifications modules)"
    "hyprctl:hyprland:the compositor (0.55+ with a Lua config)"
    "curl:curl:weather, update checks, downloads"
    "tar:tar:unpacking downloads"
    "xdg-open:xdg-utils:opening files and links"
)
OPTIONAL=(
    "pw-play:pipewire:UI sound effects"
    "wpctl:wireplumber:audio device routing"
    "pactl:pipewire-pulse:volume and audio devices (PulseAudio compatibility)"
    "qsb:qt6-shadertools:recompiling the Liquid Glass shader (precompiled .qsb files are shipped)"
    "wl-copy:wl-clipboard:clipboard"
    "cliphist:cliphist:clipboard history"
    "grim:grim:screenshots"
    "slurp:slurp:screenshot region picker"
    "wf-recorder:wf-recorder:screen recording"
    "hyprpicker:hyprpicker:color picker"
    "nmcli:networkmanager:Wi-Fi in Control Center"
    "bluetoothctl:bluez-utils:Bluetooth (also needs the bluetooth service, enabled below)"
    "rfkill:util-linux:Bluetooth / Airplane Mode (unblocking the adapter)"
    "brightnessctl:brightnessctl:display brightness"
    "playerctl:playerctl:media keys (play / pause / next / previous)"
    "powerprofilesctl:power-profiles-daemon:power profiles / Game Mode"
    "inotifywait:inotify-tools:live wallpaper watching, Trash watching"
    "hyprsunset:hyprsunset:Night Shift"
    "notify-send:libnotify:notifications from scripts, update notices"
    "awww:awww:setting the wallpaper"
    "mpvpaper:mpvpaper:animated (video) wallpapers"
    "ffmpeg:ffmpeg:video wallpaper thumbnails and previews"
    "zenity:zenity:file pickers (image widgets, Settings folders)"
    "magick:imagemagick:profile picture conversion"
    "fastfetch:fastfetch:About This Linux"
    "rsync:rsync:faster, safer file sync in the installer"
    "jq:jq:wallpaper helpers (reading the dock / shell settings)"
    "python3:python:UI sound generation and AirDrop"
    "kitty:kitty:the default terminal"
    "hypridle:hypridle:lock on idle (optional)"
)
# libraries / fonts / packages without a command to test: arch-package:what-for   (a|b = first one the repositories have)
LIBS=(
    "qt6-declarative:Qt Quick (QML)"
    "qt6-wayland:Qt Wayland support"
    "qt6-svg:SVG app icons"
    "qt6-shadertools:shader tools"
    "inter-font|ttf-inter:the Inter font"
    "noto-fonts:fallback fonts"
    "noto-fonts-emoji:emoji font"
    "papirus-icon-theme:an icon theme for app icons"
    "mesa:OpenGL drivers (Qt Quick draws with OpenGL; needed on every GPU)"
    "xdg-desktop-portal-hyprland:screen sharing and screenshots through portals"
    "polkit:privilege prompts"
)
LIBS_LOCK=(
    "hyprlock:the PAM stack MacLock checks passwords with (/etc/pam.d/hyprlock)"
)

PM=""            # pacman | dnf | apt
SUDO=""
CAN_INSTALL=1
detect_pm() {
    if have pacman; then PM=pacman
    elif have dnf; then PM=dnf
    elif have apt-get; then PM=apt
    fi
    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        if have sudo; then SUDO="sudo"; elif have doas; then SUDO="doas"; fi
        # unattended updates (systemd timer) cannot type a password: only install when sudo works without one
        if [ "$UPDATE_MODE" = 1 ]; then
            if [ "$SUDO" = sudo ] && sudo -n true >/dev/null 2>&1; then SUDO="sudo -n"; else CAN_INSTALL=0; fi
        fi
    fi
}

# arch package name(s) -> package name(s) for this distro, alternatives separated by "|" ("" = unknown, skipped)
pkg_for() {
    local p="$1"
    case "$PM" in
        pacman) printf '%s' "$p" ;;
        dnf) case "$p" in
                pipewire) echo pipewire-utils ;; pipewire-pulse) echo pipewire-pulseaudio ;;
                qt6-shadertools) echo qt6-qtshadertools ;; qt6-declarative) echo qt6-qtdeclarative ;;
                qt6-wayland) echo qt6-qtwayland ;; qt6-svg) echo qt6-qtsvg ;; networkmanager) echo NetworkManager ;;
                bluez-utils) echo bluez ;; "inter-font|ttf-inter") echo rsms-inter-fonts ;;
                noto-fonts) echo google-noto-sans-fonts ;; noto-fonts-emoji) echo "google-noto-color-emoji-fonts|google-noto-emoji-fonts" ;;
                imagemagick) echo ImageMagick ;; python) echo python3 ;; awww|mpvpaper|cliphist) echo "$p" ;; *) printf '%s' "${p%%|*}" ;;
             esac ;;
        apt) case "$p" in
                pipewire) echo pipewire-bin ;; pipewire-pulse) echo pipewire-pulse ;; qt6-shadertools) echo qt6-shader-baker ;;
                networkmanager) echo network-manager ;; bluez-utils) echo bluez ;; libnotify) echo libnotify-bin ;;
                "inter-font|ttf-inter") echo fonts-inter ;; noto-fonts) echo fonts-noto-core ;;
                noto-fonts-emoji) echo fonts-noto-color-emoji ;; python) echo python3 ;; qt6-declarative|qt6-wayland|qt6-svg) echo "" ;;
                *) printf '%s' "${p%%|*}" ;;
             esac ;;
    esac
}
pkg_installed() { # distro package name
    case "$PM" in
        pacman) pacman -Qq "$1" >/dev/null 2>&1 ;;
        dnf) rpm -q "$1" >/dev/null 2>&1 ;;
        apt) dpkg -s "$1" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}
pkg_available() { # in the distro's repositories?
    case "$PM" in
        pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
        dnf) dnf -q info "$1" >/dev/null 2>&1 ;;
        apt) apt-cache show "$1" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}
# first alternative of "a|b" that is installed / available (empty if none)
first_installed() { local a; IFS='|' read -ra alts <<<"$1"; for a in "${alts[@]}"; do pkg_installed "$a" && { printf '%s' "$a"; return 0; }; done; return 1; }
first_available() { local a; IFS='|' read -ra alts <<<"$1"; for a in "${alts[@]}"; do pkg_available "$a" && { printf '%s' "$a"; return 0; }; done; return 1; }

install_packages() { # install_packages <distro package names...>
    [ "$#" -gt 0 ] || return 0
    if [ "$CAN_INSTALL" != 1 ]; then
        warn "cannot ask for a password in an unattended update; install these yourself: $*"; return 1
    fi
    if [ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ]; then
        warn "no sudo/doas found: install these yourself: $*"; return 1
    fi
    case "$PM" in
        pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
        dnf)    $SUDO dnf install -y "$@" ;;
        apt)    $SUDO apt-get install -y "$@" ;;
    esac
}

# On Arch: build yay-bin from the AUR so packages that are not in the official repositories (awww, mpvpaper, sometimes
# quickshell) can be installed too.
AUR_HELPER=""
find_aur_helper() { AUR_HELPER=""; if have yay; then AUR_HELPER=yay; elif have paru; then AUR_HELPER=paru; fi; }
bootstrap_aur_helper() {
    [ "$PM" = pacman ] && [ "$(id -u)" -ne 0 ] && [ "$CAN_INSTALL" = 1 ] || return 1
    [ "$UPDATE_MODE" = 1 ] && return 1          # never build an AUR helper unattended
    confirm "No AUR helper found. Install yay (built from the AUR) to get packages that are not in the official repositories?" y || return 1
    install_packages git base-devel || return 1
    local tmp; tmp=$(mktemp -d)
    if git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" >/dev/null 2>&1 \
       && (cd "$tmp/yay-bin" && makepkg -si --noconfirm); then
        rm -rf "$tmp"; ok "yay installed"; find_aur_helper; return 0
    fi
    rm -rf "$tmp"; warn "could not build yay"; return 1
}

# quickshell (and a few others) are not in every repository: try an AUR helper / the Fedora COPR
MANUAL_LIST=()
install_extra_sources() {
    local missing=("$@") p
    [ "${#missing[@]}" -gt 0 ] || return 0
    case "$PM" in
        pacman)
            find_aur_helper
            [ -n "$AUR_HELPER" ] || bootstrap_aur_helper || true
            if [ -n "$AUR_HELPER" ] && [ "$CAN_INSTALL" = 1 ]; then
                for p in "${missing[@]}"; do
                    say "  $p is not in the official repositories: trying the AUR ($AUR_HELPER)"
                    "$AUR_HELPER" -S --needed --noconfirm "$p" || { warn "could not install $p from the AUR"; MANUAL_LIST+=("$p"); }
                done
            else
                warn "not in the official repositories: ${missing[*]} (install an AUR helper such as yay, then: yay -S ${missing[*]})"
                MANUAL_LIST+=("${missing[@]}")
            fi ;;
        dnf)
            if [ "$CAN_INSTALL" = 1 ] && printf '%s\n' "${missing[@]}" | grep -qx quickshell; then
                say "  quickshell: enabling the errornospam/quickshell COPR"
                $SUDO dnf copr enable -y errornospam/quickshell && $SUDO dnf install -y quickshell || { warn "could not install quickshell"; MANUAL_LIST+=(quickshell); }
                missing=("${missing[@]/quickshell}")
            fi
            for p in "${missing[@]}"; do [ -n "$p" ] && MANUAL_LIST+=("$p"); done
            printf '%s\n' "${missing[@]}" | grep -qx hyprland && warn "hyprland is not in your repositories: see https://wiki.hyprland.org"
            ;;
        apt)
            warn "not in the Debian/Ubuntu repositories: ${missing[*]}. Build them from source: https://quickshell.org and https://wiki.hyprland.org"
            MANUAL_LIST+=("${missing[@]}") ;;
    esac
}

# Video wallpapers need mpvpaper (+ ffmpeg for thumbnails). check_deps already tries to install it; this makes sure it
# is not silently skipped, and says exactly what to run when the package manager cannot provide it.
ensure_mpvpaper() {
    have mpvpaper && return 0
    [ -n "$PM" ] || { warn "mpvpaper is missing: video wallpapers need it"; return 0; }
    local failed=0 m
    for m in "${MANUAL_LIST[@]:-}"; do [ "$m" = mpvpaper ] && failed=1; done
    if [ "$failed" = 0 ] && [ "$CAN_INSTALL" = 1 ] && confirm "Install mpvpaper now (needed for video wallpapers)?" y; then
        if pick=$(first_available mpvpaper); then install_packages "$pick" || true
        else install_extra_sources mpvpaper; fi
    fi
    if have mpvpaper; then ok "mpvpaper installed"; return 0; fi
    case "$PM" in
        pacman) warn "mpvpaper is not installed: video wallpapers will not work. Run:  yay -S mpvpaper   (or paru -S mpvpaper)" ;;
        dnf)    warn "mpvpaper is not installed: video wallpapers will not work. It is not in the Fedora repositories: build it from https://github.com/GhostNaN/mpvpaper" ;;
        *)      warn "mpvpaper is not installed: video wallpapers will not work. Install it with your package manager or build it from https://github.com/GhostNaN/mpvpaper" ;;
    esac
}

check_deps() {
    step "Checking dependencies"
    detect_pm
    [ -n "$PM" ] || warn "no supported package manager (pacman, dnf, apt) found: dependencies can only be listed, not installed"
    local to_install=() entry cmd pkg why p dp
    local libs=("${LIBS[@]}")
    [ "$SKIP_LOCK" = 1 ] || libs+=("${LIBS_LOCK[@]}")

    for entry in "${REQUIRED[@]}"; do
        IFS=: read -r cmd pkg why <<<"$entry"
        if have "$cmd"; then ok "$cmd"; else warn "missing: $cmd  ($why)"; to_install+=("$pkg"); fi
    done
    for entry in "${OPTIONAL[@]}"; do
        IFS=: read -r cmd pkg why <<<"$entry"
        if have "$cmd"; then ok "$cmd"; else say "  ${D}- not found: $cmd  ($why)${N}"; to_install+=("$pkg"); fi
    done
    for entry in "${libs[@]}"; do
        IFS=: read -r pkg why <<<"$entry"
        dp=$(pkg_for "$pkg")
        [ -n "$dp" ] || continue
        if [ -n "$PM" ] && first_installed "$dp" >/dev/null; then ok "${pkg%%|*}"; else say "  ${D}- not found: ${pkg%%|*}  ($why)${N}"; to_install+=("$pkg"); fi
    done

    # translate to this distro's names, drop duplicates / unknown ones, split into "repo" and "needs another source"
    local repo=() extra=() seen=" " pick
    for p in "${to_install[@]}"; do
        dp=$(pkg_for "$p"); [ -n "$dp" ] || continue
        case "$seen" in *" $dp "*) continue ;; esac; seen="$seen$dp "
        [ -n "$PM" ] && first_installed "$dp" >/dev/null && continue
        if [ -n "$PM" ] && pick=$(first_available "$dp"); then repo+=("$pick"); else extra+=("${dp%%|*}"); fi
    done

    if [ "${#repo[@]}" -eq 0 ] && [ "${#extra[@]}" -eq 0 ]; then
        ok "all dependencies are installed"
    elif [ -z "$PM" ]; then
        say "  Install the missing tools by hand (see the list above)."
    else
        say ""
        say "  Missing packages (${PM}): ${repo[*]:-none}${extra:+  | other sources: ${extra[*]}}"
        if [ "$CAN_INSTALL" != 1 ]; then
            warn "a newer MacShell may need: ${repo[*]} ${extra[*]}. Run the installer in a terminal to install them: bash install.sh --deps-only"
        elif confirm "Install them now?" y; then
            if [ "${#repo[@]}" -gt 0 ]; then
                install_packages "${repo[@]}" || {
                    warn "the package manager failed on the whole list, retrying one by one"
                    for p in "${repo[@]}"; do install_packages "$p" >/dev/null 2>&1 || { warn "could not install $p"; MANUAL_LIST+=("$p"); }; done
                }
            fi
            install_extra_sources "${extra[@]}"
        else
            say "  Skipped. Install them later with your package manager, then run the installer again."
        fi
    fi

    if have fc-list && ! fc-list 2>/dev/null | grep -qi "Inter"; then
        warn "the Inter font was not found (the shell falls back to another font)"
    fi
    if [ "${#MANUAL_LIST[@]}" -gt 0 ]; then
        warn "still missing, install by hand: ${MANUAL_LIST[*]}"
    fi
    check_hyprland_version
    ensure_mpvpaper

    # whatever is still missing among the required tools
    for entry in "${REQUIRED[@]}"; do
        IFS=: read -r cmd pkg why <<<"$entry"
        if ! have "$cmd"; then
            [ "$UPDATE_MODE" = 1 ] && continue
            confirm "Required tool '$cmd' is still missing. Continue anyway?" n || die "install '$cmd' and run the installer again"
            break
        fi
    done
}

# MacShell needs Hyprland 0.55+ (Lua config). Only a warning: the version can be unreadable outside a session.
check_hyprland_version() {
    local v="" maj min
    if have hyprctl; then v=$(hyprctl version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true); fi
    [ -n "$v" ] || { have Hyprland && v=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true); }
    [ -n "$v" ] || return 0
    v="${v#v}"; maj="${v%%.*}"; min="${v#*.}"; min="${min%%.*}"
    if [ "$maj" -eq 0 ] 2>/dev/null && [ "$min" -lt 55 ] 2>/dev/null; then
        warn "Hyprland $v found: MacShell needs 0.55 or newer (Lua config). Window actions, Alt+Tab focus and the Settings window need it."
    else
        ok "Hyprland $v"
    fi
}

# Services a fresh Arch install does not start by itself: bluetoothd (Bluetooth), NetworkManager (Wi-Fi),
# power-profiles-daemon (power profiles / Game Mode) and the PipeWire user services (volume, sound).
unit_exists() { systemctl cat "$1" >/dev/null 2>&1; }
unit_on() { systemctl is-enabled --quiet "$1" 2>/dev/null || systemctl is-active --quiet "$1" 2>/dev/null; }
enable_services() {
    [ "$SKIP_SERVICES" = 1 ] && return 0
    have systemctl || return 0
    systemctl show-environment >/dev/null 2>&1 || return 0          # not running under systemd (container, chroot)
    local s="" entry unit why todo=()
    [ "$(id -u)" -ne 0 ] && s="${SUDO:-sudo}"
    if have bluetoothctl && unit_exists bluetooth.service && ! systemctl is-active --quiet bluetooth.service 2>/dev/null; then
        todo+=("bluetooth.service|Bluetooth does nothing without it")
    fi
    if have powerprofilesctl && unit_exists power-profiles-daemon.service && ! unit_on power-profiles-daemon.service \
       && ! unit_on tlp.service && ! unit_on auto-cpufreq.service; then
        todo+=("power-profiles-daemon.service|power profiles and Game Mode need it")
    fi
    if have nmcli && unit_exists NetworkManager.service && ! unit_on NetworkManager.service \
       && ! unit_on systemd-networkd.service && ! unit_on iwd.service && ! unit_on connman.service && ! unit_on dhcpcd.service; then
        todo+=("NetworkManager.service|Wi-Fi in Control Center needs it, and nothing else manages your network")
    fi
    if [ "${#todo[@]}" -gt 0 ]; then
        step "System services"
        for entry in "${todo[@]}"; do
            IFS='|' read -r unit why <<<"$entry"
            if confirm "Enable and start $unit ($why)?" y; then
                if $s systemctl enable --now "$unit"; then ok "$unit enabled and started"; else warn "could not enable $unit: run  sudo systemctl enable --now ${unit%.service}"; fi
            fi
        done
    fi
    # PipeWire (user services): normally socket-activated; start them when nothing does
    if systemctl --user show-environment >/dev/null 2>&1; then
        local pw=() u
        for u in pipewire.service pipewire-pulse.service wireplumber.service; do
            systemctl --user cat "$u" >/dev/null 2>&1 || continue
            systemctl --user is-active --quiet "$u" 2>/dev/null && continue
            systemctl --user is-enabled --quiet "$u" 2>/dev/null && continue
            pw+=("$u")
        done
        if [ "${#pw[@]}" -gt 0 ] && confirm "Enable the audio services (${pw[*]}); volume and sound need them?" y; then
            systemctl --user enable --now "${pw[@]}" >/dev/null 2>&1 && ok "audio services enabled" || warn "could not enable ${pw[*]}"
        fi
    fi
    return 0
}

# ───────────────────────── environment, folders, shaders ─────────────────────────
write_env_template() {
    mkdir -p "$ENV_DIR"
    [ -f "$ENV_DIR/env" ] && return 0
    cat > "$ENV_DIR/env" <<'ENVF'
# MacShell environment. macshell-start reads this file before it starts the shell.
# One "export NAME=value" per line; remove the # to use a line.

# Icon theme for the Dock and Spotlight. Left empty, the start script picks your GTK icon theme, else Papirus,
# WhiteSur, Tela, Adwaita or breeze, whichever is installed.
#export QS_ICON_THEME=Papirus-Dark

# Qt theming through qt6ct (only if you installed and configured it; it then also decides the icon theme)
#export QT_QPA_PLATFORMTHEME=qt6ct

# Older graphics (old Intel / AMD, some laptops): if the shell is slow or draws wrongly, try these one at a time
#export QSG_RHI_BACKEND=opengl        # use OpenGL, not Vulkan
#export QSG_RENDER_LOOP=basic         # simpler render loop
#export QT_QUICK_BACKEND=software     # last resort: software drawing (no Liquid Glass)
ENVF
    ok "environment file -> $ENV_DIR/env"
}

ensure_dirs() {
    mkdir -p "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Screenshots" 2>/dev/null || true
}

find_qsb() {
    local q
    for q in qsb qsb6 qsb-qt6 /usr/lib/qt6/bin/qsb /usr/lib64/qt6/bin/qsb /usr/lib/qt/bin/qsb; do
        if have "$q"; then printf '%s' "$q"; return 0; fi
    done
    return 1
}
# compile every shader that has no .qsb next to it (they normally ship precompiled)
build_shaders() { # build_shaders <installed-dir>
    local d="$1" q f n=0
    q=$(find_qsb) || { return 0; }
    for f in "$d"/*.frag; do
        [ -f "$f" ] || continue
        [ -f "$f.qsb" ] && continue
        if "$q" --qt6 -o "$f.qsb" "$f" >/dev/null 2>&1; then n=$((n+1)); else warn "could not compile $(basename "$f")"; rm -f "$f.qsb"; fi
    done
    [ "$n" -gt 0 ] && ok "$n shader(s) compiled with qsb" || true
    return 0
}

# settings for older computers: no live window capture or magnification, plain blur
json_merge() { # json_merge <file> <json-object>
    local f="$1" obj="$2"
    mkdir -p "$(dirname "$f")"
    if [ ! -s "$f" ]; then printf '%s\n' "$obj" > "$f"; return 0; fi
    if have python3; then
        python3 - "$f" "$obj" <<'PY'
import json, sys
f, add = sys.argv[1], json.loads(sys.argv[2])
try: cur = json.load(open(f))
except Exception: cur = {}
cur.update(add)
json.dump(cur, open(f, "w"), indent=2)
PY
        return $?
    fi
    return 1
}
apply_low_power() {
    step "Low-power settings (older computers)"
    local ok1=0 ok2=0
    json_merge "$CONFIG_HOME/macdock/settings.json" '{"windowCapture": false, "showThumbs": false, "magnificationEnabled": false, "dockStyle": "blur"}' && ok1=1
    json_merge "$CONFIG_HOME/macbar/settings.json" '{"barStyle": "blur", "glassRealtime": false}' && ok2=1
    if [ "$ok1" = 1 ] && [ "$ok2" = 1 ]; then
        ok "live window capture, magnification and Liquid Glass are off"
        say "  Restart MacShell (log out and in) so it reads them. Turn things back on in Settings."
    else
        warn "could not edit the settings files (python3 missing?). In Settings turn off: Dock Behavior > Live window capture, Magnification, and set the Menu Bar style to Normal Blur."
    fi
}

# ───────────────────────── doctor ─────────────────────────
detect_icon_theme() {
    local t="" f c
    for f in "$CONFIG_HOME/gtk-3.0/settings.ini" "$CONFIG_HOME/gtk-4.0/settings.ini"; do
        [ -n "$t" ] && break
        [ -f "$f" ] && t=$(sed -n 's/^gtk-icon-theme-name *= *//p' "$f" | head -n1 || true)
    done
    has_theme() { [ -f "/usr/share/icons/$1/index.theme" ] || [ -f "$HOME/.local/share/icons/$1/index.theme" ] || [ -f "$HOME/.icons/$1/index.theme" ]; }
    if [ -n "$t" ] && has_theme "$t"; then printf '%s' "$t"; return 0; fi
    for c in Papirus-Dark Papirus WhiteSur-dark WhiteSur Tela Adwaita breeze Numix; do
        has_theme "$c" && { printf '%s' "$c"; return 0; }
    done
    return 1
}

run_doctor() {
    step "MacShell doctor"
    local bad=0 t u
    d_ok()  { ok "$*"; }
    d_bad() { warn "$*"; bad=$((bad+1)); }

    # install
    if [ -f "$DEST/shell.qml" ]; then d_ok "MacShell is installed ($DEST, $(state_get installed | cut -c1-12))"; else d_bad "MacShell is not installed in $DEST: run  bash install.sh"; fi
    [ -f "$LOCK_DEST/shell.qml" ] && d_ok "MacLock is installed" || say "  ${D}- MacLock is not installed${N}"
    [ -x "$LINK_DIR/macshell-start" ] && d_ok "start script: $LINK_DIR/macshell-start" || d_bad "macshell-start is missing: run  bash install.sh  again"
    case ":$PATH:" in *":$LINK_DIR:"*) d_ok "$LINK_DIR is in PATH" ;; *) d_bad "$LINK_DIR is not in your PATH (add it to ~/.profile or your shell config, or run the tools with their full path)" ;; esac

    # session
    have qs && d_ok "quickshell: $(qs --version 2>/dev/null | head -n1)" || d_bad "quickshell (qs) is not installed"
    check_hyprland_version
    if [ -f "$HYPR_DIR/hyprland.lua" ]; then
        if grep -Eq "macshell-start|(qs|quickshell)[[:space:]]+(-c|--config)[[:space:]]+$NAME" "$HYPR_DIR/hyprland.lua"; then d_ok "autostart is in hyprland.lua"
        else d_bad "hyprland.lua does not start MacShell: run  bash install.sh  to add the autostart"; fi
        if [ -f "$HYPR_DIR/hyprland.conf" ] && grep -q 'exec-once.*\(macshell\|MacShell\)' "$HYPR_DIR/hyprland.conf"; then
            warn "hyprland.conf also has a MacShell line, but Hyprland reads hyprland.lua and ignores it"; fi
    elif [ -f "$HYPR_DIR/hyprland.conf" ]; then
        if grep -Eq "macshell-start|(qs|quickshell)[[:space:]]+(-c|--config)[[:space:]]+$NAME" "$HYPR_DIR/hyprland.conf"; then d_ok "autostart is in hyprland.conf"
        else d_bad "hyprland.conf does not start MacShell: run  bash install.sh  to add the autostart"; fi
    else
        d_bad "no Hyprland config found in $HYPR_DIR"
    fi
    if pgrep -f "(qs|quickshell).*(-c|--config)[[:space:]]+$NAME" >/dev/null 2>&1; then d_ok "MacShell is running"; else say "  ${D}- MacShell is not running right now${N}"; fi

    # environment
    if [ -n "${QS_ICON_THEME:-}" ]; then d_ok "icon theme (QS_ICON_THEME): $QS_ICON_THEME"
    elif [ -n "${QT_QPA_PLATFORMTHEME:-}" ]; then d_ok "icon theme comes from the Qt platform theme ($QT_QPA_PLATFORMTHEME)"
    elif t=$(detect_icon_theme); then d_ok "icon theme: $t (macshell-start sets QS_ICON_THEME for the shell)"
    else d_bad "no icon theme found: Dock icons will be blank. Install one (sudo pacman -S papirus-icon-theme)"; fi
    [ -f "$ENV_DIR/env" ] && d_ok "your environment file: $ENV_DIR/env" || say "  ${D}- no $ENV_DIR/env yet (the installer creates it)${N}"
    if have fc-list && fc-list 2>/dev/null | grep -qi "Inter"; then d_ok "Inter font"; else d_bad "Inter font missing (sudo pacman -S inter-font)"; fi

    # graphics
    if ls /dev/dri/renderD* >/dev/null 2>&1; then d_ok "GPU render node found"; else d_bad "no /dev/dri/renderD*: Quickshell needs OpenGL (install mesa and your GPU driver)"; fi
    have lspci && lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n2 | sed 's/^/    GPU: /'
    if [ -f "$DEST/liquidglass.frag.qsb" ]; then d_ok "Liquid Glass shader is built"; else d_bad "liquidglass.frag.qsb is missing: install qt6-shadertools and run bash install.sh"; fi

    # services
    if have systemctl && systemctl show-environment >/dev/null 2>&1; then
        have bluetoothctl && { systemctl is-active --quiet bluetooth.service 2>/dev/null && d_ok "bluetooth service is running" || d_bad "bluetooth service is not running: sudo systemctl enable --now bluetooth"; }
        have nmcli && { systemctl is-active --quiet NetworkManager.service 2>/dev/null && d_ok "NetworkManager is running" || d_bad "NetworkManager is not running (Wi-Fi in Control Center): sudo systemctl enable --now NetworkManager"; }
        have powerprofilesctl && { systemctl is-active --quiet power-profiles-daemon.service 2>/dev/null && d_ok "power-profiles-daemon is running" || say "  ${D}- power-profiles-daemon is not running (power profiles / Game Mode)${N}"; }
        if systemctl --user show-environment >/dev/null 2>&1; then
            for u in pipewire wireplumber; do
                systemctl --user is-active --quiet "$u.service" 2>/dev/null && d_ok "$u is running" || d_bad "$u is not running: systemctl --user enable --now $u"
            done
        fi
    fi
    [ -e /etc/pam.d/hyprlock ] && d_ok "/etc/pam.d/hyprlock (MacLock passwords)" || d_bad "/etc/pam.d/hyprlock is missing: install hyprlock"

    # helper scripts
    for u in macshell-setwall.sh macshell-gaming.sh macshell-wallpause.sh macshell-wallpaper.sh maclock.sh; do
        [ -x "$SCRIPTS_DIR/$u" ] && d_ok "helper: $u" || d_bad "helper script missing: $SCRIPTS_DIR/$u (video wallpapers / Game Mode / lock need it): run  bash install.sh"
    done
    have mpvpaper && d_ok "mpvpaper is installed" || say "  ${D}- mpvpaper is not installed (animated wallpapers)${N}"
    have jq || d_bad "jq is missing (the wallpaper helpers read settings with it)"

    # wallpaper
    if have awww; then
        d_ok "awww is installed"
        if awww query >/dev/null 2>&1; then d_ok "awww daemon is running"; else say "  ${D}- awww daemon is not running (macshell-start / the shell start it)${N}"; fi
        if grep -q '"wpRestorePath"' "$CONFIG_HOME/macbar/settings.json" 2>/dev/null; then d_ok "the shell remembers your wallpaper and puts it back at login"
        else say "  ${D}- pick a wallpaper once in the wallpaper picker: the shell then restores it after every reboot${N}"; fi
    else
        d_bad "awww is not installed: the wallpaper picker cannot set the real wallpaper"
    fi

    # conflicts
    for u in waybar hyprpanel ags dunst mako swaync nwg-dock-hyprland; do
        pgrep -x "$u" >/dev/null 2>&1 && d_bad "$u is running and overlaps with MacShell (stop it; dunst / mako / swaync also own the notification service)"
    done

    # version
    if have curl; then
        local inst latest
        inst=$(state_get installed); latest=$(RESOLVED_ID=""; resolve_version >/dev/null 2>&1 && printf '%s' "$RESOLVED_ID" || true)
        if [ -z "$latest" ]; then say "  ${D}- could not reach GitHub to look for updates${N}"
        elif [ "$latest" = "$inst" ]; then d_ok "up to date (${inst:0:12})"
        else warn "an update is available (${inst:0:12} -> ${latest:0:12}): run  bash install.sh"; fi
    fi
    echo
    if [ "$bad" -eq 0 ]; then printf '%sEverything looks good.%s\n' "$G" "$N"; else printf '%s%s problem(s) found%s (see the lines marked !).\n' "$Y" "$bad" "$N"; fi
}

# ───────────────────────── menu (every interactive run) ─────────────────────────
BIND_HELP_URL="https://github.com/0-ss/MacShell#hyprland-configuration-lua"
maybe_menu() {
    [ "$MODE_FLAG" = 1 ] || [ "$ASSUME_YES" = 1 ] && return 0
    [ -r /dev/tty ] && [ -w /dev/tty ] || return 0
    local inst ans latest
    inst=$(state_get installed)
    say ""
    if [ -f "$STATE_DIR/state.env" ] && [ -d "$DEST" ]; then say "${B}MacShell${N} (installed: ${inst:-unknown})"; else say "${B}MacShell${N} (not installed yet)"; fi
    {
        printf '\n  1) Install shell\n'
        printf '  2) Check for updates\n'
        printf '  3) Uninstall shell\n'
        printf '  4) Bind help\n'
        printf '  q) Quit\n\n'
        printf 'Choose [1]: '
    } >/dev/tty
    read -r ans </dev/tty || ans=""
    case "${ans:-1}" in
        1) return 0 ;;
        2)
            have curl || die "curl is required to check for updates"
            step "Checking for updates"
            latest=$(RESOLVED_ID=""; resolve_version >/dev/null 2>&1 && printf '%s' "$RESOLVED_ID" || true)
            if [ -z "$latest" ]; then warn "could not reach GitHub, check your connection"; exit 1; fi
            if [ ! -f "$STATE_DIR/state.env" ] || [ ! -d "$DEST" ]; then
                say "  MacShell is not installed (latest: ${latest:0:12})"
                confirm "Install it now?" y && return 0
                exit 0
            fi
            if [ "$latest" = "$inst" ]; then ok "up to date (${latest:0:12})"; exit 0; fi
            say "  installed: ${inst:0:12}"
            say "  latest:    ${latest:0:12}"
            confirm "An update is available. Install it now?" y && return 0
            exit 0
            ;;
        3)
            confirm "Remove MacShell and MacLock (your settings are kept)?" n && do_uninstall
            exit 0
            ;;
        4)
            say "  Opening: $BIND_HELP_URL"
            if have xdg-open; then nohup xdg-open "$BIND_HELP_URL" >/dev/null 2>&1 & fi
            exit 0
            ;;
        *) exit 0 ;;
    esac
}

# ───────────────────────── GitHub helpers ─────────────────────────
CURL=(curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused)
gh_api() { # gh_api <accept> <url>
    "${CURL[@]}" --max-time 20 ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} -H "Accept: $1" "$2"
}
latest_release() {
    gh_api application/vnd.github+json "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true
}
branch_sha() {
    local s
    s=$(gh_api application/vnd.github.sha "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null | head -c 40 || true)
    # the unauthenticated API allows 60 requests an hour: git does not count against that
    if ! [[ "$s" =~ ^[0-9a-f]{40}$ ]] && have git; then
        s=$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" 2>/dev/null | cut -c1-40 | head -n1 || true)
    fi
    [[ "$s" =~ ^[0-9a-f]{40}$ ]] && printf '%s' "$s" || true
}
resolve_version() {
    [ -n "$RESOLVED_ID" ] && return 0
    local rel sha
    if [ -n "$REF" ]; then
        RESOLVED_ID="$REF"
        if [[ "$REF" =~ ^[0-9a-f]{7,40}$ ]]; then RESOLVED_TYPE="commit"; else RESOLVED_TYPE="release"; fi
        return 0
    fi
    if [ "$CHANNEL" = release ]; then
        rel=$(latest_release)
        if [ -n "$rel" ]; then RESOLVED_ID="$rel"; RESOLVED_TYPE="release"; return 0; fi
    fi
    sha=$(branch_sha)
    if [ -n "$sha" ]; then RESOLVED_ID="$sha"; RESOLVED_TYPE="branch"; return 0; fi
    die "could not reach GitHub (repo $REPO). Check your connection, or use --from-dir with a local copy."
}

# --check: compare the installed version with GitHub, change nothing
run_check() {
    step "Checking for updates"
    have curl || die "curl is required"
    resolve_version
    local inst; inst=$(state_get installed)
    inst="${inst:-none}"
    if [ "$inst" = "$RESOLVED_ID" ]; then
        ok "up to date (${RESOLVED_ID:0:12})"; exit 0
    fi
    say "  installed: ${inst:0:12}"
    say "  latest:    ${RESOLVED_ID:0:12} ($RESOLVED_TYPE)"
    say "  Update available. Run ./install.sh, or: macshell-update update"
    exit 10
}

# the folder of one component. A component is a folder called <name> that holds shell.qml (e.g. MacShell/, MacLock/),
# found anywhere near the top of the source. For MacShell only, a shell.qml that sits in the repository root
# (and is not inside the MacLock folder) is accepted too.
find_component_root() { # find_component_root <source-root> <name> [allow-root-fallback]
    local src="$1" name="$2" f
    f=$(find "$src" -maxdepth 3 -type f -name shell.qml -path "*/$name/shell.qml" -not -path '*/.git/*' 2>/dev/null \
        | awk '{ print length($0) " " $0 }' | sort -n | head -n1 | cut -d' ' -f2-)
    if [ -z "$f" ] && [ "${3:-}" = fallback ]; then
        f=$(find "$src" -maxdepth 3 -type f -name shell.qml -not -path '*/.git/*' -not -path "*/$LOCK_NAME/*" 2>/dev/null \
            | awk '{ print length($0) " " $0 }' | sort -n | head -n1 | cut -d' ' -f2-)
    fi
    [ -n "$f" ] && dirname "$f"
}

# ───────────────────────── get the files ─────────────────────────
TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }
trap cleanup EXIT

fetch_source() {
    if [ -n "$FROM_DIR" ]; then
        [ -d "$FROM_DIR" ] || die "--from-dir: $FROM_DIR is not a folder"
        SRC_ROOT=$(cd "$FROM_DIR" && pwd)
        [ -n "$RESOLVED_ID" ] || { RESOLVED_ID="local"; RESOLVED_TYPE="local"; }
        return 0
    fi
    local here="${BASH_SOURCE[0]:-}"
    if [ -z "$REF" ] && [ -n "$here" ] && [ -f "$here" ]; then
        local d; d=$(cd "$(dirname "$here")" && pwd)
        if [ -f "$d/shell.qml" ] || [ -f "$d/MacShell/shell.qml" ] || [ -f "$d/MacLock/shell.qml" ]; then
            SRC_ROOT="$d"
            if git -C "$d" rev-parse --short HEAD >/dev/null 2>&1; then
                RESOLVED_ID=$(git -C "$d" rev-parse HEAD); RESOLVED_TYPE="commit"
            else
                RESOLVED_ID="local"; RESOLVED_TYPE="local"
            fi
            # a clone: is GitHub ahead of it? then install the newer version instead (unless --local / uncommitted edits)
            if [ "$LOCAL_ONLY" != 1 ] && [ "$UPDATE_MODE" != 1 ] && [ "$RESOLVED_TYPE" = commit ] && have curl \
               && [ -z "$(git -C "$d" status --porcelain 2>/dev/null)" ]; then
                local remote; remote=$(branch_sha)
                if [ -n "$remote" ] && [ "$remote" != "$RESOLVED_ID" ]; then
                    step "A newer version is on GitHub (${RESOLVED_ID:0:7} -> ${remote:0:7}): installing that"
                    RESOLVED_ID=""; RESOLVED_TYPE=""
                    local here_skip=1
                fi
            fi
            if [ -z "${here_skip:-}" ]; then
                step "Installing from the local copy in $d"
                return 0
            fi
        fi
    fi
    resolve_version
    step "Downloading $REPO ($RESOLVED_TYPE: $RESOLVED_ID)"
    TMP=$(mktemp -d)
    mkdir -p "$TMP/src"
    "${CURL[@]}" --max-time 180 "https://github.com/$REPO/archive/$RESOLVED_ID.tar.gz" | tar -xz --strip-components=1 -C "$TMP/src" \
        || die "download failed (https://github.com/$REPO/archive/$RESOLVED_ID.tar.gz)"
    SRC_ROOT="$TMP/src"
    ok "downloaded"
}

backup_current() { # backup_current <dest> <name>
    local dest="$1" name="$2"
    [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ] || return 0
    [ -n "$BACKUP_TS" ] || BACKUP_TS=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$BACKUP_DIR/$BACKUP_TS"
    cp -a "$dest" "$BACKUP_DIR/$BACKUP_TS/$name"
    ok "previous $name saved to $BACKUP_DIR/$BACKUP_TS/"
    # keep the three newest
    ls -1dt "$BACKUP_DIR"/*/ 2>/dev/null | tail -n +4 | while read -r old; do rm -rf "$old"; done
}

# repository files that are not part of a Quickshell config (MacLock is excluded so it never ends up inside MacShell)
EXCLUDES=(.git .github install.sh macshell-update macshell-start hypr-macshell README.md README LICENSE LICENSE.md docs screenshots scripts sounds "$LOCK_NAME")
LOCK_EXCLUDES=(.git .github)

sync_files() { # sync_files <source-folder> <dest> <exclude>...
    local qml_root="$1" dest="$2" e; shift 2
    mkdir -p "$dest"
    if have rsync; then
        local args=()
        for e in "$@"; do args+=("--exclude=/$e"); done
        # --delay-updates: every file lands in place at the very end, so Quickshell never reloads a half-copied folder
        rsync -a --delete --delay-updates "${args[@]}" "$qml_root"/ "$dest"/
    else
        # no rsync: copy into a sibling folder first, then move the files in
        local stage; stage=$(mktemp -d "$dest.stage.XXXXXX")
        local targs=()
        for e in "$@"; do targs+=("--exclude=./$e"); done
        tar -C "$qml_root" "${targs[@]}" -cf - . | tar -C "$stage" -xf -
        find "$dest" -mindepth 1 -delete
        cp -a "$stage"/. "$dest"/
        rm -rf "$stage"
    fi
}

# the start script used by the autostart line: waits for the compositor, never starts a second copy,
# restarts the shell when it crashes (and gives up when it dies right away over and over)
write_start_script() {
    mkdir -p "$BIN_DIR" "$LINK_DIR"
    cat > "$BIN_DIR/.macshell-start.new" <<'START'
#!/bin/sh
# macshell-start: starts MacShell for the Hyprland session (the autostart line runs this).
#   macshell-start [ConfigName]      default: MacShell
# Your own environment variables go in ~/.config/macshell/env   (for example: export QS_ICON_THEME=Papirus)
NAME="${1:-MacShell}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; export PATH

command -v qs >/dev/null 2>&1 || { echo "macshell-start: qs (quickshell) not found in PATH" >&2; exit 1; }

# wait (up to 20 s) until the Wayland socket exists
i=0
while [ "$i" -lt 100 ]; do
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$WAYLAND_DISPLAY" ]; then break; fi
    i=$((i + 1)); sleep 0.2
done

# already running for this user? then there is nothing to do
if pgrep -u "$(id -u)" -f "(^|/)(qs|quickshell)( .*)? (-c|--config) $NAME( |\$)" >/dev/null 2>&1; then exit 0; fi

# ── environment: the variables Qt and Quickshell need, whatever started this script ──
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-Hyprland}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
# your own settings win over the defaults below
if [ -f "$CONF/macshell/env" ]; then set -a; . "$CONF/macshell/env"; set +a; fi
# icon theme: yours (QS_ICON_THEME or qt6ct), else the GTK one, else the first well-known theme that is installed
if [ -z "${QS_ICON_THEME:-}" ] && [ -z "${QT_QPA_PLATFORMTHEME:-}" ]; then
    has_theme() { [ -f "/usr/share/icons/$1/index.theme" ] || [ -f "$HOME/.local/share/icons/$1/index.theme" ] || [ -f "$HOME/.icons/$1/index.theme" ]; }
    t=""
    for f in "$CONF/gtk-3.0/settings.ini" "$CONF/gtk-4.0/settings.ini"; do
        [ -n "$t" ] && break
        [ -f "$f" ] && t=$(sed -n 's/^gtk-icon-theme-name *= *//p' "$f" | head -n1)
    done
    if [ -z "$t" ] || ! has_theme "$t"; then
        t=""
        for c in Papirus-Dark Papirus WhiteSur-dark WhiteSur Tela Adwaita breeze Numix; do
            if has_theme "$c"; then t="$c"; break; fi
        done
    fi
    [ -n "$t" ] && export QS_ICON_THEME="$t"
fi
# portals and services started later by D-Bus / systemd need to know the session too
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP >/dev/null 2>&1
fi

# ── wallpaper: awww forgets it at every reboot. If awww was used before (and no other wallpaper tool runs), bring it back
# now; the shell also re-applies the wallpaper you picked, a few seconds later.
if command -v awww-daemon >/dev/null 2>&1 && [ -n "$(ls -A "${XDG_CACHE_HOME:-$HOME/.cache}/awww" 2>/dev/null)" ] \
   && ! pgrep -x hyprpaper >/dev/null 2>&1 && ! pgrep -x swaybg >/dev/null 2>&1 && ! pgrep -x mpvpaper >/dev/null 2>&1; then
    (
        awww query >/dev/null 2>&1 || setsid awww-daemon >/dev/null 2>&1 &
        n=0; while [ "$n" -lt 20 ]; do awww query >/dev/null 2>&1 && break; n=$((n + 1)); sleep 0.25; done
        awww restore >/dev/null 2>&1
    ) &
fi

fast=0
while :; do
    start=$(date +%s)
    qs -c "$NAME"
    rc=$?
    case "$rc" in 0|130|143) exit 0 ;; esac          # quit on purpose (qs kill / Ctrl+C / SIGTERM)
    if [ $(( $(date +%s) - start )) -lt 5 ]; then fast=$((fast + 1)); else fast=0; fi
    if [ "$fast" -ge 5 ]; then
        msg="MacShell keeps crashing right after it starts. Run:  qs -c $NAME   and read the log (or: bash install.sh --doctor)."
        echo "macshell-start: $msg" >&2
        command -v notify-send >/dev/null 2>&1 && notify-send -u critical "MacShell" "$msg"
        exit 1
    fi
    sleep 1
done
START
    chmod +x "$BIN_DIR/.macshell-start.new" && mv -f "$BIN_DIR/.macshell-start.new" "$BIN_DIR/macshell-start"
    ln -sf "$BIN_DIR/macshell-start" "$LINK_DIR/macshell-start"
}

# Find the helper tree (a folder called hypr-macshell near the top of the source).
find_hypr_root() { # find_hypr_root <source-root>
    local d
    d=$(find "$1" -maxdepth 3 -type d -name hypr-macshell -not -path '*/.git/*' 2>/dev/null \
        | awk '{ print length($0) " " $0 }' | sort -n | head -n1 | cut -d' ' -f2-)
    [ -n "$d" ] && printf '%s' "$d"
}

# Copy the helper tree into ~/.config/hypr-macshell. Files that ship with MacShell are updated; the user's own
# custom/ folder is only filled in where files are missing, and extra files the user added are never deleted.
install_hypr_tree() { # install_hypr_tree <hypr-macshell source folder>
    local src="$1" f n
    [ -d "$src/scripts" ] || return 1
    backup_current "$HYPR_MAC_DIR" hypr-macshell
    mkdir -p "$HYPR_MAC_DIR"
    if have rsync; then
        rsync -a --exclude=/custom/ "$src"/ "$HYPR_MAC_DIR"/
        [ -d "$src/custom" ] && rsync -a --ignore-existing "$src/custom"/ "$HYPR_MAC_DIR/custom"/
    else
        tar -C "$src" --exclude=./custom -cf - . | tar -C "$HYPR_MAC_DIR" -xf -
        if [ -d "$src/custom" ]; then
            (cd "$src/custom" && find . -type f) | while IFS= read -r f; do
                [ -e "$HYPR_MAC_DIR/custom/$f" ] || { mkdir -p "$(dirname "$HYPR_MAC_DIR/custom/$f")"; cp -p "$src/custom/$f" "$HYPR_MAC_DIR/custom/$f"; }
            done
        fi
    fi
    # the files ship with a __HOME__ placeholder for absolute paths
    for f in hypridle.conf hyprlock/colors.conf; do
        [ -f "$HYPR_MAC_DIR/$f" ] && sed -i "s|__HOME__|$HOME|g" "$HYPR_MAC_DIR/$f"
    done
    find "$HYPR_MAC_DIR" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true
    n=$(find "$HYPR_MAC_DIR/scripts" -maxdepth 1 -type f \( -name 'macshell-*.sh' -o -name 'macshell-*.py' \) | wc -l)
    ok "$n helper script(s) -> $SCRIPTS_DIR"
    ok "session config, hypridle / hyprlock files -> $HYPR_MAC_DIR"
    # app launchers (Finder, Photos, Clock, ...)
    n=0
    if [ -d "$src/applications" ]; then
        mkdir -p "$APPS_DIR"
        for f in "$src"/applications/*.desktop; do [ -f "$f" ] && { cp -f "$f" "$APPS_DIR/"; n=$((n+1)); }; done
        [ "$n" -gt 0 ] && { ok "$n app launcher(s) -> $APPS_DIR"; have update-desktop-database && update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true; }
    fi
    # icons
    n=0
    if [ -d "$src/icons" ]; then
        mkdir -p "$ICONS_DIR"
        for f in "$src"/icons/*.svg; do [ -f "$f" ] && { cp -f "$f" "$ICONS_DIR/"; n=$((n+1)); }; done
        [ "$n" -gt 0 ] && { ok "$n icon(s) -> $ICONS_DIR"; have gtk-update-icon-cache && gtk-update-icon-cache -q -t "$DATA_HOME/icons/hicolor" >/dev/null 2>&1 || true; }
    fi
    # Apple emoji font preference
    if [ -f "$src/75-apple-emoji.conf" ]; then
        mkdir -p "$FONTCONF_DIR"; cp -f "$src/75-apple-emoji.conf" "$FONTCONF_DIR/"
        have fc-cache && fc-cache -f >/dev/null 2>&1 || true
        ok "emoji font rule -> $FONTCONF_DIR"
    fi
    return 0
}

install_extras() {
    local root="$1" f n hroot
    # helper tree: scripts (Game Mode, video wallpapers, AirDrop, lock), session config, launchers, icons
    hroot=$(find_hypr_root "$root" || true)
    if [ -n "$hroot" ] && install_hypr_tree "$hroot"; then
        :
    else
        # older layout: loose macshell-*.sh / macshell-*.py files somewhere in the source
        n=0
        while IFS= read -r f; do
            mkdir -p "$SCRIPTS_DIR"
            cp -f "$f" "$SCRIPTS_DIR/$(basename "$f")"; chmod +x "$SCRIPTS_DIR/$(basename "$f")"; n=$((n+1))
        done < <(find "$root" -type f \( -name 'macshell-*.sh' -o -name 'macshell-*.py' \) -not -path '*/.git/*' 2>/dev/null)
        if [ "$n" -gt 0 ]; then ok "$n helper script(s) -> $SCRIPTS_DIR"; else warn "no helper scripts (macshell-*.sh) and no hypr-macshell/ folder in the source: Game Mode and video wallpapers will not work (the repository is missing hypr-macshell/)"; fi
    fi
    # sounds
    n=0
    while IFS= read -r f; do
        mkdir -p "$SOUNDS_DIR"; cp -f "$f" "$SOUNDS_DIR/"; n=$((n+1))
    done < <(find "$root" -type f -name '*.wav' -path '*sounds*' -not -path '*/.git/*' 2>/dev/null)
    [ "$n" -gt 0 ] && ok "$n sound(s) -> $SOUNDS_DIR"
    # synthesize the UI sounds that are still missing (existing files are never replaced)
    if [ -f "$SCRIPTS_DIR/macshell-make-sounds.py" ] && have python3; then
        python3 "$SCRIPTS_DIR/macshell-make-sounds.py" "$SOUNDS_DIR" >/dev/null 2>&1 && ok "UI sounds ready in $SOUNDS_DIR" || warn "could not generate the UI sounds"
    elif [ "$n" -eq 0 ]; then
        warn "no UI sounds installed (the repo ships none and python3 / macshell-make-sounds.py is missing)"
    fi
    # the update tool
    f=$(find "$root" -maxdepth 3 -type f -name macshell-update -not -path '*/.git/*' 2>/dev/null | head -n1)
    if [ -n "$f" ]; then
        mkdir -p "$BIN_DIR" "$LINK_DIR"
        cp -f "$f" "$BIN_DIR/.macshell-update.new" && chmod +x "$BIN_DIR/.macshell-update.new" && mv -f "$BIN_DIR/.macshell-update.new" "$BIN_DIR/macshell-update"
        ln -sf "$BIN_DIR/macshell-update" "$LINK_DIR/macshell-update"
        ok "update tool -> $BIN_DIR/macshell-update"
    else
        warn "macshell-update not found in the source: update checks will not work"
    fi
    write_start_script
    ok "start script -> $BIN_DIR/macshell-start"
    if [ "$SKIP_AUTOSTART" != 1 ] || [ "$UPDATE_MODE" = 1 ]; then write_macshell_lua; fi
    # a copy of this installer: run  macshell-install  any time to update, check dependencies or run the doctor
    if [ -f "$root/install.sh" ]; then
        cp -f "$root/install.sh" "$BIN_DIR/.macshell-install.new" && chmod +x "$BIN_DIR/.macshell-install.new" \
            && mv -f "$BIN_DIR/.macshell-install.new" "$BIN_DIR/macshell-install" && ln -sf "$BIN_DIR/macshell-install" "$LINK_DIR/macshell-install"
        ok "installer -> $LINK_DIR/macshell-install"
    fi
}

write_state() {
    mkdir -p "$STATE_DIR"
    {
        echo "repo=$REPO"
        echo "branch=$BRANCH"
        echo "channel=$RESOLVED_TYPE"
        echo "channel_pref=$CHANNEL"
        echo "installed=$RESOLVED_ID"
        echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "dest=$DEST"
        echo "lock_dest=$LOCK_DEST"
        echo "lock_installed=$([ -n "${LOCK_ROOT:-}" ] && echo yes || echo no)"
    } > "$STATE_DIR/state.env"
}

# ───────────────────────── Hyprland autostart ─────────────────────────
# Hyprland 0.55+ reads hyprland.lua and ignores hyprland.conf when both exist, so the autostart goes where Hyprland
# actually looks. (The old installer always wrote "exec-once" into hyprland.conf, which a Lua session never reads.)
START_CMD() { printf 'sh %s' "$LINK_DIR/macshell-start"; }

write_macshell_lua() {
    mkdir -p "$HYPR_DIR"
    local f="$HYPR_DIR/macshell.lua"
    if [ -f "$f" ] && ! grep -qF -- "$MACLUA_BEGIN" "$f" && [ ! -e "$f.macshell-backup" ]; then
        cp -p "$f" "$f.macshell-backup"
        ok "saved the existing $f to $f.macshell-backup"
    fi
    {
        printf '%s\n' "$MACLUA_BEGIN"
        cat <<'MACSHELL_LUA'
-- autostart (remove other bars / docks / notification daemons first).
-- install.sh adds this for you; macshell-start waits for the compositor and restarts the shell if it crashes.
hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("sh ~/.local/bin/macshell-start")
end)
-- The Settings window floats and centres itself when it opens, so it needs no window rule.

-- keybinds (the name after -c is the config folder name, case-sensitive)
local qs = "qs -c MacShell ipc call "

hl.bind("SUPER + V",          hl.dsp.exec_cmd(qs .. "spotlight clipboard"))
hl.bind("SUPER + period",     hl.dsp.exec_cmd(qs .. "spotlight emoji"))
hl.bind("SUPER + Space",      hl.dsp.exec_cmd(qs .. "spotlight toggle"))
hl.bind("ALT + TAB",          hl.dsp.exec_cmd(qs .. "switcher next"))
hl.bind("CTRL + ALT + W",     hl.dsp.exec_cmd(qs .. "wallpapers toggle"))
hl.bind("PRINT",              hl.dsp.exec_cmd(qs .. "screenshot region"))

-- Hardware keys (laptop buttons too): volume, mute, brightness, media. MacShell handles them itself and shows its
-- on-screen display. If the shell is not running, wpctl / brightnessctl do the work instead.
-- "locked" keeps the keys working on the lock screen. Any earlier bind on the same key is dropped first, so a key never fires twice.
local function hw(action, fallback)
    return "sh -c '" .. qs .. "hardware " .. action .. " >/dev/null 2>&1 || " .. fallback .. "'"
end
local hwkeys = {
    { "XF86AudioRaiseVolume",  hw("volumeUp",       "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),   true  },
    { "XF86AudioLowerVolume",  hw("volumeDown",     "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        true  },
    { "XF86AudioMute",         hw("mute",           "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       false },
    { "XF86AudioMicMute",      hw("micMute",        "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     false },
    { "XF86MonBrightnessUp",   hw("brightnessUp",   "brightnessctl -q set 5%+"),                         true  },
    { "XF86MonBrightnessDown", hw("brightnessDown", "brightnessctl -q -n1 set 5%-"),                     true  },
    { "XF86KbdBrightnessUp",   "brightnessctl -q -d '*kbd_backlight*' set 10%+",                         true  },
    { "XF86KbdBrightnessDown", "brightnessctl -q -d '*kbd_backlight*' set 10%-",                         true  },
    { "XF86AudioPlay",         "playerctl play-pause",                                                   false },
    { "XF86AudioPause",        "playerctl pause",                                                        false },
    { "XF86AudioNext",         "playerctl next",                                                         false },
    { "XF86AudioPrev",         "playerctl previous",                                                     false },
}
for _, k in ipairs(hwkeys) do
    pcall(hl.unbind, k[1])
    hl.bind(k[1], hl.dsp.exec_cmd(k[2]), { locked = true, repeating = k[3] })
end

-- MacShell's own windows (Settings, About This Linux): translucent like a macOS window, and no Hyprland border
-- (these windows draw their own edge). Blur size / passes are global in Hyprland (decoration.blur), not per window.
hl.window_rule({
    name = "macshell-settings",
    match = { title = "^macshell Settings$" },
    opacity = "0.82 0.85 1",          -- active, inactive, fullscreen
    border_size = 0,
    rounding = 12,
})
hl.window_rule({
    name = "macshell-about",
    match = { title = "^About This Linux$" },
    opacity = "0.82 0.85 1",
    border_size = 0,
    rounding = 18,
})

-- MacLock (lock screen)
hl.bind("SUPER + L",          hl.dsp.exec_cmd("sh ~/.config/quickshell/MacLock/lock-via-ipc.sh"))
MACSHELL_LUA
        printf '%s\n' "$MACLUA_END"
    } > "$f"
    ok "MacShell autostart and keybinds -> $f"
}

lua_block() { # lua_block <with-rules 0|1>
    printf '%s\n' "$MARK_BEGIN"
    printf '%s\n' '-- Load the generated MacShell autostart and keybind module.'
    printf '%s\n' 'require("macshell")'
    if [ "${1:-0}" = 1 ]; then
        printf '%s\n' '-- Liquid Glass: blur behind the shell surfaces'
        printf '%s\n' 'hl.layer_rule({ name = "macdock",  match = { namespace = "macdock"  }, blur = true, ignore_alpha = 0.2,  no_anim = true })'
        printf '%s\n' 'hl.layer_rule({ name = "macspot",  match = { namespace = "macspot"  }, blur = true, ignore_alpha = 0.05, no_anim = true })'
        printf '%s\n' 'hl.layer_rule({ name = "macbarbg", match = { namespace = "macbarbg" }, blur = true, ignore_alpha = 0.05, no_anim = true })'
        printf '%s\n' 'hl.layer_rule({ name = "macshot",  match = { namespace = "macshot"  }, no_anim = true })'
    fi
    printf '%s\n' "$MARK_END"
}

add_autostart() {
    [ "$SKIP_AUTOSTART" = 1 ] && return 0
    step "Hyprland autostart"
    local conf="$HYPR_DIR/hyprland.conf" lua="$HYPR_DIR/hyprland.lua" rules=0
    if [ -f "$lua" ]; then
        if grep -qF -- "$MARK_BEGIN" "$lua"; then
            # refresh our own block (keeps the start command current), keeps everything else as it is
            local had_rules=0; grep -q 'hl.layer_rule({ name = "macdock"' "$lua" && had_rules=1
            sed -i "\|$MARK_BEGIN|,\|$MARK_END|d" "$lua"
            { echo; lua_block "$had_rules"; } >> "$lua"
            ok "autostart block in $lua refreshed"
        elif grep -Eq "macshell-start|(qs|quickshell)[[:space:]]+(-c|--config)[[:space:]]+$NAME" "$lua"; then
            if ! grep -qF 'require("macshell")' "$lua" && ! grep -qF 'macshell.lua' "$lua"; then
                cp -f "$lua" "$lua.macshell-backup"
                { echo; lua_block 0; } >> "$lua"
                ok "added the MacShell module loader to $lua (backup: $lua.macshell-backup)"
                have hyprctl && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && hyprctl reload >/dev/null 2>&1 && ok "Hyprland config reloaded"
            else
                ok "$lua already loads the MacShell module"
            fi
        else
            if [ "$SKIP_RULES" != 1 ] && ! grep -q 'namespace *= *"macdock"' "$lua" \
               && confirm "Also add the Liquid Glass layer rules (blur behind the Dock and menus)?" y; then rules=1; fi
            cp -f "$lua" "$lua.macshell-backup"
            { echo; lua_block "$rules"; } >> "$lua"
            ok "added the autostart to $lua (backup: $lua.macshell-backup)"
            have hyprctl && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && hyprctl reload >/dev/null 2>&1 && ok "Hyprland config reloaded"
        fi
    elif [ -f "$conf" ]; then
        if grep -qF -- "$CONF_BEGIN" "$conf"; then
            sed -i "\|$CONF_BEGIN|,\|$CONF_END|d" "$conf"
            { echo; printf '%s\nexec-once = %s\n%s\n' "$CONF_BEGIN" "$(START_CMD)" "$CONF_END"; } >> "$conf"
            ok "autostart line in $conf refreshed"
        elif grep -Eq "macshell-start|(qs|quickshell)[[:space:]]+(-c|--config)[[:space:]]+$NAME" "$conf"; then
            ok "$conf already starts MacShell"
        else
            cp -f "$conf" "$conf.macshell-backup"
            { echo; printf '%s\nexec-once = %s\n%s\n' "$CONF_BEGIN" "$(START_CMD)" "$CONF_END"; } >> "$conf"
            ok "added the autostart to $conf (backup: $conf.macshell-backup)"
            say "  Glass blur needs layer rules, see the README (Hyprland configuration)."
        fi
    else
        say "  No Hyprland config found in $HYPR_DIR. Start MacShell from your autostart with:"
        say '      Lua:   require("macshell")'
        say "      conf:  exec-once = $(START_CMD)"
    fi
    if pgrep -x waybar >/dev/null 2>&1 || pgrep -x hyprpanel >/dev/null 2>&1; then
        warn "another bar (waybar / hyprpanel) is running: stop it, MacShell has its own menu bar"
    fi
    local d
    for d in dunst mako swaync; do
        pgrep -x "$d" >/dev/null 2>&1 && warn "$d is running and owns the notification service: systemctl --user disable --now $d (MacShell shows notifications itself)"
    done
    return 0
}

show_lock_hint() {
    local lua="$HYPR_DIR/hyprland.lua"
    say "  Lock screen:         bind a key to  sh $LOCK_DEST/lock-via-ipc.sh"
    if [ -f "$lua" ] || [ ! -f "$HYPR_DIR/hyprland.conf" ]; then
        say "      hl.bind(\"SUPER + L\", hl.dsp.exec_cmd(\"sh ~/.config/quickshell/$LOCK_NAME/lock-via-ipc.sh\"))"
    else
        say "      bind = SUPER, L, exec, sh ~/.config/quickshell/$LOCK_NAME/lock-via-ipc.sh"
    fi
    [ -e /etc/pam.d/hyprlock ] || warn "/etc/pam.d/hyprlock not found: MacLock checks passwords with that PAM stack (install hyprlock, or add the file)"
}

# ───────────────────────── main ─────────────────────────
[ "$DOCTOR" = 1 ] && { run_doctor; exit 0; }
[ "$CHECK_ONLY" = 1 ] && run_check
maybe_menu
[ "$SKIP_DEPS" = 1 ] || check_deps
if [ "$DEPS_ONLY" = 1 ]; then enable_services; write_env_template; ensure_dirs; ok "dependencies done"; exit 0; fi
SRC_ROOT=""
fetch_source

QML_ROOT=$(find_component_root "$SRC_ROOT" "$NAME" fallback || true)
[ -n "$QML_ROOT" ] || die "shell.qml not found in the source: is this the MacShell repository?"
LOCK_ROOT=""
if [ "$SKIP_LOCK" != 1 ]; then
    LOCK_ROOT=$(find_component_root "$SRC_ROOT" "$LOCK_NAME" || true)
    [ -n "$LOCK_ROOT" ] || warn "MacLock was not found in the source: only MacShell will be installed"
fi

step "Installing MacShell to $DEST"
backup_current "$DEST" "$NAME"
sync_files "$QML_ROOT" "$DEST" "${EXCLUDES[@]}"
ok "MacShell files copied"
if [ -n "$LOCK_ROOT" ]; then
    step "Installing MacLock to $LOCK_DEST"
    backup_current "$LOCK_DEST" "$LOCK_NAME"
    sync_files "$LOCK_ROOT" "$LOCK_DEST" "${LOCK_EXCLUDES[@]}"
    chmod +x "$LOCK_DEST"/*.sh 2>/dev/null || true
    ok "MacLock files copied"
fi
install_extras "$SRC_ROOT"
build_shaders "$DEST"
write_env_template
ensure_dirs
write_state
# make Quickshell reload once, after every file is in place
touch "$DEST/shell.qml"
[ -n "$LOCK_ROOT" ] && touch "$LOCK_DEST/shell.qml" || true

if [ "$UPDATE_MODE" = 1 ]; then
    # the autostart block may need a newer start command: refresh it only if we wrote it
    if [ -f "$HYPR_DIR/hyprland.lua" ] && grep -qF -- "$MARK_BEGIN" "$HYPR_DIR/hyprland.lua"; then SKIP_AUTOSTART=0; add_autostart >/dev/null 2>&1 || true; fi
    ok "updated to $RESOLVED_ID"
    exit 0
fi

enable_services
add_autostart
[ "$LOW_POWER" = 1 ] && apply_low_power
case "$AUTO_UPDATE" in
    yes) setup_auto_update ;;
    no)  remove_auto_update ;;
    *)   if [ "$ASSUME_YES" != 1 ] && confirm "Check for updates automatically every day and install them?" n; then setup_auto_update; fi ;;
esac

echo
printf '%sMacShell %s is installed%s.%s\n' "$G" "${RESOLVED_ID:0:12}" "${LOCK_ROOT:+ (with MacLock)}" "$N"
say "  Start it:            sh $LINK_DIR/macshell-start      (or: qs -c $NAME)"
[ -n "$LOCK_ROOT" ] && show_lock_hint
say "  Update / repair:     macshell-install      (or run ./install.sh again: it looks for news on GitHub)"
say "  Find problems:       macshell-install --doctor"
say "  Roll back:           macshell-update rollback"
case ":$PATH:" in *":$LINK_DIR:"*) ;; *) say "  Note: add $LINK_DIR to your PATH to use 'macshell-update' from a terminal." ;; esac
if have qs && pgrep -f "(qs|quickshell).*(-c|--config)[[:space:]]+$NAME" >/dev/null 2>&1; then
    say "  MacShell is running and reloads by itself."
elif have qs && [ -n "${WAYLAND_DISPLAY:-}" ] && confirm "Start MacShell now?" y; then
    nohup sh "$LINK_DIR/macshell-start" >/dev/null 2>&1 &
    ok "started"
fi
