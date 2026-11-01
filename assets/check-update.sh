#!/bin/sh
# check-update.sh: asks GitHub whether a newer MacShell exists and prints ONE line of JSON. It never downloads or installs.
#   {"status":"available|uptodate|error","latest":"0.4.1","current":"0.4.0","url":"https://github.com/..."}
# Used by Settings (MacBar.qml: checkForUpdates). Repository: MACSHELL_REPO (default 0-ss/MacShell), branch: MACSHELL_BRANCH (main).
REPO="${MACSHELL_REPO:-0-ss/MacShell}"
BRANCH="${MACSHELL_BRANCH:-main}"
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
ROOT=$(dirname "$HERE")
STATE="${XDG_DATA_HOME:-$HOME/.local/share}/macshell/state.env"

is_ver() { printf '%s' "$1" | grep -Eq '^v?[0-9]+(\.[0-9]+)*$'; }
# the highest valid version among the arguments (the VERSION file is easy to forget: AboutApp.qml also carries "MacShell x.y.z")
max_ver() {
    best=""
    for v in "$@"; do
        is_ver "$v" || continue
        v="${v#v}"
        if [ -z "$best" ] || [ "$(printf '%s\n%s\n' "$best" "$v" | sort -V | tail -n1)" != "$best" ]; then best="$v"; fi
    done
    printf '%s' "$best"
}
about_ver() { grep -oE 'MacShell [0-9]+(\.[0-9]+)+' | head -n1 | cut -d' ' -f2; }
out() { printf '{"status":"%s","latest":"%s","current":"%s","url":"%s"}\n' "$1" "$2" "$3" "$4"; exit 0; }

command -v curl >/dev/null 2>&1 || out error "" "" "https://github.com/$REPO"
CURL="curl -fsSL --retry 2 --retry-delay 1 --max-time 15"

# installed version: the VERSION file of the running shell, else what the installer remembered
cur=""
v1=""; v2=""
[ -f "$ROOT/VERSION" ] && v1=$(tr -d ' \t\r\n' < "$ROOT/VERSION" | cut -c1-40)
[ -f "$ROOT/AboutApp.qml" ] && v2=$(about_ver < "$ROOT/AboutApp.qml")
cur=$(max_ver "$v1" "$v2")
if ! is_ver "$cur" && [ -f "$STATE" ]; then
    cur=$(sed -n 's/^installed_version=//p' "$STATE" | head -n1 | tr -d ' \t\r')
    is_ver "$cur" || cur=$(sed -n 's/^installed=//p' "$STATE" | head -n1 | tr -d ' \t\r')
fi
is_ver "$cur" || cur=""
cur="${cur#v}"

# newest version: the latest release (the redirect has no API rate limit), else the API, else VERSION on the main branch
latest=""; url="https://github.com/$REPO"
final=$($CURL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null || true)
case "$final" in */releases/tag/*) latest="${final##*/releases/tag/}"; latest="${latest%%[?#]*}" ;; esac
if ! is_ver "$latest"; then
    latest=$($CURL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
fi
if is_ver "$latest"; then
    url="https://github.com/$REPO/releases/latest"
else
    r1=""; r2=""; r3=""; r4=""
    r1=$($CURL "https://raw.githubusercontent.com/$REPO/$BRANCH/MacShell/VERSION" 2>/dev/null | head -n1 | tr -d ' \t\r\n')
    r2=$($CURL "https://raw.githubusercontent.com/$REPO/$BRANCH/VERSION" 2>/dev/null | head -n1 | tr -d ' \t\r\n')
    r3=$($CURL "https://raw.githubusercontent.com/$REPO/$BRANCH/MacShell/AboutApp.qml" 2>/dev/null | about_ver)
    r4=$($CURL "https://raw.githubusercontent.com/$REPO/$BRANCH/AboutApp.qml" 2>/dev/null | about_ver)
    latest=$(max_ver "$r1" "$r2" "$r3" "$r4")
fi
is_ver "$latest" || out error "" "$cur" "$url"
latest="${latest#v}"

if [ -z "$cur" ]; then out available "$latest" "" "$url"; fi
newest=$(printf '%s\n%s\n' "$latest" "$cur" | sort -V | tail -n1)
if [ "$latest" != "$cur" ] && [ "$newest" = "$latest" ]; then out available "$latest" "$cur" "$url"; fi
out uptodate "$latest" "$cur" "$url"
