# MacShell

macOS-style desktop shell for Hyprland, built on Quickshell (QML).

## Layout
- `MacShell/` — main Quickshell config (dock, menu bar, Spotlight, apps). Version in `MacShell/VERSION` and `MacShell/AboutApp.qml`; bump both together.
- `MacLock/` — lock screen, a separate Quickshell config (Python helpers for lyrics/canvas).
- `MacGreeter/` — login greeter. `MacInstaller/` — first-run installer UI.
- `hypr-macshell/` — Hyprland config module and helper scripts.
- `contrib/`, `compat/`, `docs/` — extras, compatibility shims, documentation.
- `install.sh` — installer/uninstaller. `tests/` — `test_*.mjs` (node) and `test_*.py` (unittest).

## Constraints
- `MacShell` and `MacLock` are intentionally separate Quickshell configs; do not merge or share QML between them.
- Hyprland 0.55+ Lua syntax (`hyprland.lua`, `macshell.lua`).
- Never commit `.pyc`/`__pycache__` or archives; run Python with `-B`.
- QML ids must be unique per file, including ids inside inline `sourceComponent`/delegates.

## Verify
`bash scripts/check.sh` — read-only: Python/shell syntax, `shellcheck -S error`, `qmllint` errors, node and unittest tests. Must exit 0 before committing.
