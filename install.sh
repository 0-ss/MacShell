#!/usr/bin/env bash
# MacShell installer / updater
#
#   curl -fsSL https://raw.githubusercontent.com/0-ss/MacShell/main/install.sh | bash
#   ./install.sh            (from a clone of the repository)
#
# What it does
#   1. checks the tools MacShell needs (and offers to install them on Arch)
#   2. downloads the latest release (or the latest commit of the main branch)
#   3. installs the shell to   ~/.config/quickshell/MacShell        (start it with:  qs -c MacShell)
#      the lock screen to      ~/.config/quickshell/MacLock         (lock with:  sh ~/.config/quickshell/MacLock/lock-via-ipc.sh)
#      (MacShell and MacLock are two separate Quickshell configs; neither is placed inside the other)
#      helper scripts to       ~/.config/hypr-macshell/scripts      (only if the repo ships them)
#      sounds to               ~/.local/share/sounds/macshell       (only if the repo ships them)
#      the update tool to      ~/.local/share/macshell/bin/macshell-update  (+ ~/.local/bin/macshell-update)
#   4. optionally adds an exec-once line to hyprland.conf
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
    rm -f "$LINK_DIR/macshell-update" "$BIN_DIR/macshell-update" "$STATE_DIR/state.env"
    ok "removed the update tool"
    say "Your settings were kept (~/.config/macbar, macdock, macshell, macwidgets)."
    say "If you added them, remove the 'exec-once = qs -c $NAME' line and the MacLock lock keybind from your Hyprland config."
    exit 0
fi

# ───────────────────────── dependencies ─────────────────────────
# command:arch-package:what-for
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
    "nmcli:networkmanager:Wi-Fi in Control Center"
    "bluetoothctl:bluez-utils:Bluetooth in Control Center"
    "brightnessctl:brightnessctl:display brightness"
    "powerprofilesctl:power-profiles-daemon:power profiles / Game Mode"
    "inotifywait:inotify-tools:live wallpaper watching"
    "hyprsunset:hyprsunset:Night Shift"
    "notify-send:libnotify:update notifications"
)

check_deps() {
    step "Checking dependencies"
    local miss_req=() miss_opt=() pk_all=() entry cmd pkg why
    for entry in "${REQUIRED[@]}"; do
        IFS=: read -r cmd pkg why <<<"$entry"
        if have "$cmd"; then ok "$cmd"; else warn "missing: $cmd  ($why)"; miss_req+=("$cmd"); pk_all+=("$pkg"); fi
    done
    for entry in "${OPTIONAL[@]}"; do
        IFS=: read -r cmd pkg why <<<"$entry"
        if have "$cmd"; then ok "$cmd"; else say "  ${D}- optional, not found: $cmd  ($why)${N}"; miss_opt+=("$cmd"); pk_all+=("$pkg"); fi
    done
    if have fc-list && ! fc-list 2>/dev/null | grep -qi "Inter"; then
        warn "the Inter font was not found (the shell falls back to another font). Arch: pacman -S inter-font"
    fi
    [ "${#miss_req[@]}" -eq 0 ] && [ "${#miss_opt[@]}" -eq 0 ] && return 0

    if have pacman; then
        # quickshell / hyprland are installed separately when pacman does not know them
        local installable=() p
        for p in "${pk_all[@]}"; do pacman -Si "$p" >/dev/null 2>&1 && installable+=("$p"); done
        if [ "${#installable[@]}" -gt 0 ] && confirm "Install the missing packages with pacman (${installable[*]})?" n; then
            sudo pacman -S --needed "${installable[@]}" || warn "pacman failed, continuing"
        fi
        if ! have qs; then
            warn "quickshell is not installed. Arch: 'pacman -S quickshell' or from the AUR: 'yay -S quickshell-git'"
        fi
    elif have dnf; then
        say "  Fedora: sudo dnf install curl wl-clipboard brightnessctl power-profiles-daemon NetworkManager bluez inotify-tools libnotify pipewire-utils qt6-qtshadertools"
        say "          quickshell: sudo dnf copr enable errornospam/quickshell && sudo dnf install quickshell"
    elif have apt-get; then
        say "  Debian/Ubuntu: sudo apt install curl wl-clipboard brightnessctl power-profiles-daemon network-manager bluez inotify-tools libnotify-bin pipewire-bin qt6-shader-baker"
        say "                 quickshell and Hyprland are not in the main repositories: see https://quickshell.org"
    else
        say "  Install the missing tools with your package manager (see the list above)."
    fi

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
            step "Installing from the local copy in $d"
            return 0
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
