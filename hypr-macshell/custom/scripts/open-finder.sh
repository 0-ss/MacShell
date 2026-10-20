#!/usr/bin/env bash
# Open MacShell's Finder; fall back to whatever file manager is installed if the shell isn't up.
if qs -c MacShell ipc call finder open >/dev/null 2>&1; then
    exit 0
fi
exec ~/.config/hypr-macshell/hyprland/scripts/launch_first_available.sh 'dolphin' 'nautilus' 'nemo' 'thunar' 'kitty -1 fish -c yazi'
