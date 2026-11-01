#!/usr/bin/env bash
# Add MacLock to Hypridle's pre-suspend hook without replacing existing idle settings.
# Lid-close is covered when logind's lid policy suspends the machine.
set -eu

cfg_home="${XDG_CONFIG_HOME:-$HOME/.config}"
hypr_dir="$cfg_home/hypr"
config="$hypr_dir/hypridle.conf"
lock_cmd="sh $cfg_home/quickshell/MacLock/lock-via-ipc.sh"
mkdir -p "$hypr_dir"

python3 - "$config" "$lock_cmd" <<'PY'
import os
import re
import sys
import tempfile

path, lock_cmd = sys.argv[1:]
try:
    with open(path, "r", encoding="utf-8") as f:
        original = f.read()
except FileNotFoundError:
    original = ""

if lock_cmd in original:
    changed = original
else:
    lines = original.splitlines()
    start = end = None
    depth = 0
    for i, line in enumerate(lines):
        if start is None and re.match(r"^\s*general\s*\{\s*(?:#.*)?$", line):
            start = i
            depth = 1
            continue
        if start is not None:
            code = line.split("#", 1)[0]
            depth += code.count("{") - code.count("}")
            if depth <= 0:
                end = i
                break

    if start is None:
        if original and not original.endswith("\n"):
            lines.append("")
        lines.extend(["general {", f"    before_sleep_cmd = {lock_cmd}", "}"])
    else:
        if end is None:
            lines.append("}")
            end = len(lines) - 1
        hook_idx = None
        for i in range(start + 1, end):
            if re.match(r"^\s*before_sleep_cmd\s*=", lines[i]):
                hook_idx = i
                break
        if hook_idx is None:
            lines.insert(end, f"    before_sleep_cmd = {lock_cmd}")
        else:
            line = lines[hook_idx]
            m = re.match(r"^(\s*before_sleep_cmd\s*=\s*)(.*?)(\s+#.*)?$", line)
            if m:
                existing = m.group(2).strip()
                suffix = m.group(3) or ""
                combined = f"{existing}; {lock_cmd}" if existing else lock_cmd
                lines[hook_idx] = f"{m.group(1)}{combined}{suffix}"
            else:
                lines[hook_idx] = f"    before_sleep_cmd = {lock_cmd}"
    changed = "\n".join(lines).rstrip() + "\n"

if changed != original:
    if os.path.exists(path) and not os.path.exists(path + ".macshell-backup"):
        with open(path + ".macshell-backup", "w", encoding="utf-8") as f:
            f.write(original)
    fd, tmp = tempfile.mkstemp(prefix=".hypridle.", dir=os.path.dirname(path), text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(changed)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
PY

# MacShell starts Hypridle itself; restart it so the newly written hook takes effect.
if command -v hypridle >/dev/null 2>&1; then
    pkill -x hypridle 2>/dev/null || true
    (hypridle >/dev/null 2>&1 &) 
fi
