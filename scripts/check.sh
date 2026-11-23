#!/usr/bin/env bash
# Read-only verification gate for MacShell. Run from anywhere: bash scripts/check.sh
cd "$(dirname "$0")/.." || exit 1
fail=0
step() { printf '\n== %s\n' "$1"; }
run() { "$@" || { echo "FAILED: $*"; fail=1; }; }

step "python syntax"
py_files=$(git ls-files '*.py'; echo MacShell/assets/mac-discord-ctl MacShell/assets/mac-earbuds-ctl contrib/genie/macshell-genie)
for f in $py_files; do
    run python3 -B -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f"
done

# Shell scripts, split by shebang.
sh_files="install.sh MacShell/macshell-update MacShell/assets/*.sh MacGreeter/*.sh MacGreeter/macshell-greeter* MacLock/*.sh hypr-macshell/scripts/*.sh scripts/check.sh scripts/sync-shared.sh"

step "shell syntax"
for f in $sh_files; do
    case $(head -1 "$f") in
        '#!/bin/sh'*) run sh -n "$f" ;;
        *) run bash -n "$f" ;;
    esac
done

step "shellcheck (errors only)"
if command -v shellcheck >/dev/null; then
    # shellcheck disable=SC2086 # sh_files is an intentional glob list
    run shellcheck -S error $sh_files
else
    echo "skipped: shellcheck not installed"
fi

step "shared-file sync"
run bash scripts/sync-shared.sh --check

step "qmllint (errors only)"
qmllint=/usr/lib/qt6/bin/qmllint
[ -x "$qmllint" ] || qmllint=$(command -v qmllint)
if [ -n "$qmllint" ]; then
    out=$("$qmllint" -I /usr/lib/qt6/qml --unqualified disable --missing-property disable \
        --missing-type disable --import disable --unused-imports disable \
        --attached-property-reuse disable --unresolved-type disable \
        --block-scope-var-declaration disable --incompatible-type disable \
        MacShell/*.qml MacLock/*.qml MacGreeter/*.qml MacInstaller/*.qml 2>&1)
    if printf '%s\n' "$out" | grep -q '^Error:'; then
        printf '%s\n' "$out" | grep -A3 '^Error:'
        fail=1
    fi
    # Plan 002 fixed the only id-shadows-member; keep it locked out.
    if printf '%s\n' "$out" | grep -q '\[id-shadows-member\]'; then
        printf '%s\n' "$out" | grep -B2 -A3 '\[id-shadows-member\]'
        fail=1
    fi
else
    echo "skipped: qmllint not installed"
fi

step "node tests"
for t in tests/test_*.mjs; do
    run node "$t"
done

step "python tests"
run python3 -B -m unittest discover -s tests -v

echo
[ "$fail" = 0 ] && echo "ALL CHECKS PASSED" || echo "CHECKS FAILED"
exit "$fail"
