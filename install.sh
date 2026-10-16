#!/usr/bin/env bash
# MacShell installer / updater
#
#   curl -fsSL https://raw.githubusercontent.com/0-ss/MacShell/main/install.sh | bash
#   ./install.sh            (from a clone of the repository)
#
# What it does
#   1. checks the tools, libraries and fonts MacShell / MacLock need and installs the missing ones
#      (pacman, dnf or apt; quickshell from the AUR / the Fedora COPR when the main repositories lack it)
#   2. downloads the latest release (or the latest commit of the main branch)
#   3. installs the shell to   ~/.config/quickshell/MacShell        (start it with:  qs -c MacShell)
#      the lock screen to      ~/.config/quickshell/MacLock         (lock with:  sh ~/.config/quickshell/MacLock/lock-via-ipc.sh)
#      (MacShell and MacLock are two separate Quickshell configs; neither is placed inside the other)
#      helper scripts to       ~/.config/hypr-macshell/scripts      (only if the repo ships them)
#      sounds to               ~/.local/share/sounds/macshell       (only if the repo ships them)
#      the update tool to      ~/.local/share/macshell/bin/macshell-update  (+ ~/.local/bin/macshell-update)
#   4. optionally adds an exec-once line to hyprland.conf
#   5. optionally sets up automatic updates (a daily systemd user timer)
#
# Updates
#   Run from a clone, the installer first asks GitHub whether the repository has something newer. If it does
#   (and your clone has no uncommitted changes), it downloads the newer version and installs that automatically.
#   Use --local to install exactly what is in the clone, or --check to only look.
#
# Your settings (~/.config/macbar, macdock, macshell, macwidgets, ...) are never touched.
# Before replacing an existing install, the old one is saved to ~/.local/share/macshell/backups/ (last 3 kept).
#
# Options
#   -y, --yes             do not ask questions (answer yes)
#       --no-deps         skip the dependency check
#       --no-autostart    do not touch the Hyprland config
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
# Environment: MACSHELL_REPO (default 0-ss/MacShell), MACSHELL_BRANCH (default main), MACSHELL_DEST, MACLOCK_DEST, GITHUB_TOKEN

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
SCRIPTS_DIR="$CONFIG_HOME/hypr-macshell/scripts"
SOUNDS_DIR="$DATA_HOME/sounds/macshell"
LINK_DIR="$HOME/.local/bin"

ASSUME_YES=0
SKIP_DEPS=0
SKIP_AUTOSTART=0
SKIP_LOCK=0
CHECK_ONLY=0
LOCAL_ONLY=0
AUTO_UPDATE=""
BACKUP_TS=""
UPDATE_MODE=0
UNINSTALL=0
REF=""
FROM_DIR=""
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
        --no-autostart) SKIP_AUTOSTART=1 ;;
        --no-lock) SKIP_LOCK=1 ;;
        --check) CHECK_ONLY=1; SKIP_DEPS=1 ;;
        --local) LOCAL_ONLY=1 ;;
        --auto-update) AUTO_UPDATE=yes ;;
        --no-auto-update) AUTO_UPDATE=no ;;
        --update) UPDATE_MODE=1; SKIP_DEPS=1; SKIP_AUTOSTART=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --ref) REF="${2:-}"; shift ;;
        --from-dir) FROM_DIR="${2:-}"; shift ;;
        --resolved-id) RESOLVED_ID="${2:-}"; shift ;;
        --resolved-type) RESOLVED_TYPE="${2:-}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

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
ExecStart=$BIN_DIR/macshell-update update --yes
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
if [ "$UNINSTALL" = 1 ]; then
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
    rm -f "$LINK_DIR/macshell-update" "$BIN_DIR/macshell-update" "$STATE_DIR/state.env"
    ok "removed the update tool"
    say "Your settings were kept (~/.config/macbar, macdock, macshell, macwidgets)."
    say "If you added them, remove the 'exec-once = qs -c $NAME' line and the MacLock lock keybind from your Hyprland config."
    exit 0
fi

# ───────────────────────── dependencies ─────────────────────────
# command:arch-package:what-for   (a check by command name; package names are Arch names, translated per distro below)
REQUIRED=(
    "qs:quickshell:the shell runtime (needs the Hyprland, Screencopy, PipeWire, UPower, Mpris and Notifications modules)"
    "hyprctl:hyprland:the compositor"
    "curl:curl:weather, update checks, downloads"
    "tar:tar:unpacking downloads"
)
OPTIONAL=(
    "pw-play:pipewire:UI sound effects"
    "qsb:qt6-shadertools:recompiling the Liquid Glass shader (precompiled .qsb files are shipped)"
    "wl-copy:wl-clipboard:clipboard"
    "cliphist:cliphist:clipboard history"
    "grim:grim:screenshots"
    "wf-recorder:wf-recorder:screen recording"
    "hyprpicker:hyprpicker:color picker"
    "nmcli:networkmanager:Wi-Fi in Control Center"
    "bluetoothctl:bluez-utils:Bluetooth in Control Center"
    "brightnessctl:brightnessctl:display brightness"
    "powerprofilesctl:power-profiles-daemon:power profiles / Game Mode"
    "inotifywait:inotify-tools:live wallpaper watching"
    "hyprsunset:hyprsunset:Night Shift"
    "notify-send:libnotify:update notifications"
    "wpctl:wireplumber:audio device routing"
)
# libraries / fonts without a command to test: arch-package:what-for
LIBS=(
    "qt6-declarative:Qt Quick (QML)"
    "qt6-wayland:Qt Wayland support"
    "qt6-svg:SVG app icons"
    "qt6-shadertools:shader tools"
    "ttf-inter:the Inter font"
    "noto-fonts-emoji:emoji font"
)
LIBS_LOCK=(
    "hyprlock:the PAM stack MacLock checks passwords with (/etc/pam.d/hyprlock)"
)

PM=""            # pacman | dnf | apt
SUDO=""
detect_pm() {
    if have pacman; then PM=pacman
    elif have dnf; then PM=dnf
    elif have apt-get; then PM=apt
    fi
    if [ "$(id -u)" -ne 0 ]; then
        if have sudo; then SUDO="sudo"; elif have doas; then SUDO="doas"; fi
    fi
}

# arch package name -> package name for this distro ("" = not available / unknown, skipped)
pkg_for() {
    local p="$1"
    case "$PM" in
        pacman) printf '%s' "$p" ;;
        dnf) case "$p" in
                pipewire) echo pipewire-utils ;; qt6-shadertools) echo qt6-qtshadertools ;; qt6-declarative) echo qt6-qtdeclarative ;;
                qt6-wayland) echo qt6-qtwayland ;; qt6-svg) echo qt6-qtsvg ;; networkmanager) echo NetworkManager ;;
                bluez-utils) echo bluez ;; ttf-inter) echo rsms-inter-fonts ;; noto-fonts-emoji) echo google-noto-emoji-fonts ;;
                wireplumber) echo wireplumber ;; *) printf '%s' "$p" ;;
             esac ;;
        apt) case "$p" in
                pipewire) echo pipewire-bin ;; qt6-shadertools) echo qt6-shader-baker ;; networkmanager) echo network-manager ;;
                bluez-utils) echo bluez ;; libnotify) echo libnotify-bin ;; ttf-inter) echo fonts-inter ;;
                noto-fonts-emoji) echo fonts-noto-color-emoji ;; qt6-declarative|qt6-wayland|qt6-svg) echo "" ;;
                *) printf '%s' "$p" ;;
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

install_packages() { # install_packages <distro package names...>
    [ "$#" -gt 0 ] || return 0
    if [ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ]; then
        warn "no sudo/doas found: install these yourself: $*"; return 1
    fi
    case "$PM" in
        pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
        dnf)    $SUDO dnf install -y "$@" ;;
        apt)    $SUDO apt-get install -y "$@" ;;
    esac
}

# quickshell (and a few others) are not in every repository: try an AUR helper / the Fedora COPR
install_extra_sources() {
    local missing=("$@") p
    [ "${#missing[@]}" -gt 0 ] || return 0
    case "$PM" in
        pacman)
            local aur=""
            have yay && aur=yay; [ -z "$aur" ] && have paru && aur=paru
            if [ -n "$aur" ]; then
                for p in "${missing[@]}"; do
                    say "  $p is not in the official repositories: trying the AUR ($aur)"
                    "$aur" -S --needed --noconfirm "$p" || warn "could not install $p from the AUR"
                done
            else
                warn "not in the official repositories: ${missing[*]} (install an AUR helper such as yay, then: yay -S ${missing[*]})"
            fi ;;
        dnf)
            if printf '%s\n' "${missing[@]}" | grep -qx quickshell; then
                say "  quickshell: enabling the errornospam/quickshell COPR"
                $SUDO dnf copr enable -y errornospam/quickshell && $SUDO dnf install -y quickshell || warn "could not install quickshell"
            fi
            printf '%s\n' "${missing[@]}" | grep -qx hyprland && warn "hyprland is not in your repositories: see https://wiki.hyprland.org"
            ;;
        apt)
            warn "not in the Debian/Ubuntu repositories: ${missing[*]}. Build them from source: https://quickshell.org and https://wiki.hyprland.org" ;;
    esac
}

check_deps() {
    step "Checking dependencies"
    detect_pm
    local to_install=() unavailable=() entry cmd pkg why p dp
    local miss_req=()

    for entry in "${REQUIRED[@]}"; do
        IFS=: read -r cmd pkg why <<<"$entry"
        if have "$cmd"; then ok "$cmd"; else warn "missing: $cmd  ($why)"; miss_req+=("$cmd"); to_install+=("$pkg"); fi
    done
    for entry in "${OPTIONAL[@]}"; do
        IFS=: read -r cmd pkg why <<<"$entry"
        if have "$cmd"; then ok "$cmd"; else say "  ${D}- not found: $cmd  ($why)${N}"; to_install+=("$pkg"); fi
    done
    local libs=("${LIBS[@]}"); [ "$SKIP_LOCK" = 1 ] || libs+=("${LIBS_LOCK[@]}")
    for entry in "${libs[@]}"; do
        IFS=: read -r pkg why <<<"$entry"
        dp=$(pkg_for "$pkg")
        [ -n "$dp" ] || continue
        if [ -n "$PM" ] && pkg_installed "$dp"; then ok "$pkg"; else say "  ${D}- not found: $pkg  ($why)${N}"; to_install+=("$pkg"); fi
    done

    # translate to this distro's names, drop duplicates / unknown ones, split into "repo" and "needs another source"
    local repo=() extra=() seen=" "
    for p in "${to_install[@]}"; do
        dp=$(pkg_for "$p"); [ -n "$dp" ] || continue
        case "$seen" in *" $dp "*) continue ;; esac; seen="$seen$dp "
        [ -n "$PM" ] && pkg_installed "$dp" && continue
        if [ -n "$PM" ] && pkg_available "$dp"; then repo+=("$dp"); else extra+=("$dp"); fi
    done

    if [ "${#repo[@]}" -eq 0 ] && [ "${#extra[@]}" -eq 0 ]; then
        :
    elif [ -z "$PM" ]; then
        say "  No supported package manager (pacman, dnf, apt) found: install the missing tools by hand (see the list above)."
    else
        say ""
        say "  Missing packages (${PM}): ${repo[*]:-none}${extra:+  | other sources: ${extra[*]}}"
        if confirm "Install them now?" y; then
            [ "${#repo[@]}" -gt 0 ] && { install_packages "${repo[@]}" || warn "the package manager reported an error, continuing"; }
            install_extra_sources "${extra[@]}"
        else
            say "  Skipped. Install them later with your package manager, then run the installer again."
        fi
    fi

    if have fc-list && ! fc-list 2>/dev/null | grep -qi "Inter"; then
        warn "the Inter font was not found (the shell falls back to another font)"
    fi

    # whatever is still missing among the required tools
    for entry in "${REQUIRED[@]}"; do
        IFS=: read -r cmd pkg why <<<"$entry"
        if ! have "$cmd"; then
            confirm "Required tool '$cmd' is still missing. Continue anyway?" n || die "install '$cmd' and run the installer again"
            break
        fi
    done
}

# ───────────────────────── GitHub helpers ─────────────────────────
gh_api() { # gh_api <accept> <url>
    curl -fsSL --max-time 20 ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} -H "Accept: $1" "$2"
}
latest_release() {
    gh_api application/vnd.github+json "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true
}
branch_sha() {
    gh_api application/vnd.github.sha "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null | head -c 40 || true
}
resolve_version() {
    [ -n "$RESOLVED_ID" ] && return 0
    local rel sha
    if [ -n "$REF" ]; then
        RESOLVED_ID="$REF"
        if [[ "$REF" =~ ^[0-9a-f]{7,40}$ ]]; then RESOLVED_TYPE="commit"; else RESOLVED_TYPE="release"; fi
        return 0
    fi
    rel=$(latest_release)
    if [ -n "$rel" ]; then RESOLVED_ID="$rel"; RESOLVED_TYPE="release"; return 0; fi
    sha=$(branch_sha)
    if [ -n "$sha" ]; then RESOLVED_ID="$sha"; RESOLVED_TYPE="branch"; return 0; fi
    die "could not reach GitHub (repo $REPO). Check your connection, or use --from-dir with a local copy."
}

# --check: compare the installed version with GitHub, change nothing
run_check() {
    step "Checking for updates"
    have curl || die "curl is required"
    resolve_version
    local inst; inst=$(sed -n 's/^installed=//p' "$STATE_DIR/state.env" 2>/dev/null | head -n1 || true)
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
    curl -fsSL --max-time 180 "https://github.com/$REPO/archive/$RESOLVED_ID.tar.gz" | tar -xz --strip-components=1 -C "$TMP/src" \
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
EXCLUDES=(.git .github install.sh macshell-update README.md README LICENSE LICENSE.md docs screenshots scripts sounds "$LOCK_NAME")
LOCK_EXCLUDES=(.git .github)

sync_files() { # sync_files <source-folder> <dest> <exclude>...
    local qml_root="$1" dest="$2" e; shift 2
    mkdir -p "$dest"
    if have rsync; then
        local args=()
        for e in "$@"; do args+=("--exclude=/$e"); done
        rsync -a --delete "${args[@]}" "$qml_root"/ "$dest"/
    else
        find "$dest" -mindepth 1 -delete
        local targs=()
        for e in "$@"; do targs+=("--exclude=./$e"); done
        tar -C "$qml_root" "${targs[@]}" -cf - . | tar -C "$dest" -xf -
    fi
}

install_extras() {
    local root="$1" f n
    # helper scripts (Game Mode, wallpaper helpers)
    n=0
    while IFS= read -r f; do
        mkdir -p "$SCRIPTS_DIR"
        cp -f "$f" "$SCRIPTS_DIR/$(basename "$f")"; chmod +x "$SCRIPTS_DIR/$(basename "$f")"; n=$((n+1))
    done < <(find "$root" -type f -name 'macshell-*.sh' -not -path '*/.git/*' 2>/dev/null)
    [ "$n" -gt 0 ] && ok "$n helper script(s) -> $SCRIPTS_DIR"
    # sounds
    n=0
    while IFS= read -r f; do
        mkdir -p "$SOUNDS_DIR"; cp -f "$f" "$SOUNDS_DIR/"; n=$((n+1))
    done < <(find "$root" -type f -name '*.wav' -path '*sounds*' -not -path '*/.git/*' 2>/dev/null)
    [ "$n" -gt 0 ] && ok "$n sound(s) -> $SOUNDS_DIR"
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
}

write_state() {
    mkdir -p "$STATE_DIR"
    {
        echo "repo=$REPO"
        echo "branch=$BRANCH"
        echo "channel=$RESOLVED_TYPE"
        echo "installed=$RESOLVED_ID"
        echo "installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "dest=$DEST"
    } > "$STATE_DIR/state.env"
}

add_autostart() {
    [ "$SKIP_AUTOSTART" = 1 ] && return 0
    local conf="$CONFIG_HOME/hypr/hyprland.conf" lua
    lua=$(ls "$CONFIG_HOME"/hypr/hyprland.lua 2>/dev/null | head -n1 || true)
    if [ -f "$conf" ]; then
        if grep -Eq "(qs|quickshell)[[:space:]]+(-c|--config)[[:space:]]+$NAME" "$conf"; then
            ok "Hyprland already starts MacShell"
        elif confirm "Start MacShell automatically with Hyprland (adds a line to $conf)?" y; then
            printf '\n# MacShell\nexec-once = qs -c %s\n' "$NAME" >> "$conf"
            ok "added 'exec-once = qs -c $NAME' to $conf"
        fi
    elif [ -n "$lua" ]; then
        say "  Add this to $lua to start MacShell with Hyprland:"
        say "      hl.on(\"hyprland.start\", function() hl.exec_cmd(\"qs -c $NAME\") end)"
    else
        say "  Start MacShell with:  qs -c $NAME   (add it to your Hyprland autostart)"
    fi
    if pgrep -x waybar >/dev/null 2>&1 || pgrep -x hyprpanel >/dev/null 2>&1; then
        warn "another bar (waybar / hyprpanel) is running: stop it, MacShell has its own menu bar"
    fi
}

show_lock_hint() {
    local lua
    lua=$(ls "$CONFIG_HOME"/hypr/hyprland.lua 2>/dev/null | head -n1 || true)
    say "  Lock screen:         bind a key to  sh $LOCK_DEST/lock-via-ipc.sh"
    if [ -n "$lua" ]; then
        say "      hl.bind(\"SUPER + L\", hl.dsp.exec_cmd(\"sh ~/.config/quickshell/$LOCK_NAME/lock-via-ipc.sh\"))"
    else
        say "      bind = SUPER, L, exec, sh ~/.config/quickshell/$LOCK_NAME/lock-via-ipc.sh"
    fi
    [ -e /etc/pam.d/hyprlock ] || warn "/etc/pam.d/hyprlock not found: MacLock checks passwords with that PAM stack (install hyprlock, or add the file)"
}

# ───────────────────────── main ─────────────────────────
[ "$CHECK_ONLY" = 1 ] && run_check
[ "$SKIP_DEPS" = 1 ] || check_deps
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
write_state
# make Quickshell reload once, after every file is in place
touch "$DEST/shell.qml"
[ -n "$LOCK_ROOT" ] && touch "$LOCK_DEST/shell.qml" || true

if [ "$UPDATE_MODE" = 1 ]; then
    ok "updated to $RESOLVED_ID"
    exit 0
fi

add_autostart
case "$AUTO_UPDATE" in
    yes) setup_auto_update ;;
    no)  remove_auto_update ;;
    *)   if [ "$ASSUME_YES" != 1 ] && confirm "Check for updates automatically every day and install them?" n; then setup_auto_update; fi ;;
esac

echo
printf '%sMacShell %s is installed%s.%s\n' "$G" "$RESOLVED_ID" "${LOCK_ROOT:+ (with MacLock)}" "$N"
say "  Start it:            qs -c $NAME"
[ -n "$LOCK_ROOT" ] && show_lock_hint
say "  Check for updates:   macshell-update check      (the shell also checks by itself and tells you)"
say "  Update:              macshell-update update"
say "  Roll back:           macshell-update rollback"
case ":$PATH:" in *":$LINK_DIR:"*) ;; *) say "  Note: add $LINK_DIR to your PATH to use 'macshell-update' from a terminal." ;; esac
if have qs && pgrep -f "qs.*-c[[:space:]]+$NAME" >/dev/null 2>&1; then
    say "  MacShell is running and reloads by itself."
elif have qs && [ -n "${WAYLAND_DISPLAY:-}" ] && confirm "Start MacShell now?" y; then
    nohup qs -c "$NAME" >/dev/null 2>&1 &
    ok "started"
fi
