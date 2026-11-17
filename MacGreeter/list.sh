#!/bin/sh
# Prints one line of JSON for the greeter: the users it offers, the sessions it can start and the last choices.
# Users come from the data macshell-greeter-sync copied for the greeter; accounts that never synced are listed too (name only).
R="${1:-/var/lib/macshell-greeter}"
tab=$(printf '\t')
users=$(
    for d in "$R"/users/*/; do
        [ -f "${d}profile.json" ] || continue
        jq -c --arg u "$(basename "$d")" '. + {user: $u}' "${d}profile.json" 2>/dev/null
    done
    getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { print $1 "\t" $5 }' | while IFS="$tab" read -r u n; do
        [ -f "$R/users/$u/profile.json" ] && continue
        jq -nc --arg u "$u" --arg n "${n%%,*}" '{user: $u, name: (if $n == "" then $u else $n end)}'
    done
)
users=$(printf '%s\n' "$users" | jq -s -c '.' 2>/dev/null)
[ -n "$users" ] || users='[]'
sessions=$(
    for f in /usr/share/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        n=$(sed -n 's/^Name=//p' "$f" | head -n1)
        e=$(sed -n 's/^Exec=//p' "$f" | head -n1)
        [ -n "$e" ] && printf '%s\t%s\n' "${n:-$e}" "$e"
    done | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {name: .[0], exec: .[1]})' 2>/dev/null
)
[ -n "$sessions" ] || sessions='[]'
jq -nc --argjson u "$users" --argjson s "$sessions" \
    --arg lu "$(cat "$R/state/last-user" 2>/dev/null)" --arg ls "$(cat "$R/state/last-session" 2>/dev/null)" \
    '{users: $u, sessions: $s, lastUser: $lu, lastSession: $ls}'
