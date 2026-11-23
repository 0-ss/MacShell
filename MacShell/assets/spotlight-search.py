#!/usr/bin/env python3
"""Fast full-text + filename + metadata search & Quick Look snippet reader for MacShell Spotlight."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

SKIP_DIRS = {
    ".git",
    ".cache",
    ".local",
    ".npm",
    ".cargo",
    ".rustup",
    "node_modules",
    "__pycache__",
    ".venv",
    "venv",
    "target",
    "build",
}

TEXT_EXTS = {
    ".txt", ".md", ".markdown", ".json", ".js", ".mjs", ".ts", ".tsx", ".py",
    ".qml", ".sh", ".bash", ".fish", ".lua", ".toml", ".yaml", ".yml", ".ini",
    ".conf", ".cfg", ".css", ".html", ".xml", ".c", ".cpp", ".h", ".rs", ".go",
    ".csv", ".log", ".org", ".tex",
}


def safe_stat(p: Path) -> tuple[int, float]:
    try:
        st = p.stat()
        return int(st.st_size), float(st.st_mtime)
    except OSError:
        return 0, 0.0


def search_files(query: str, root_dir: str, limit: int = 40) -> list[dict[str, Any]]:
    q = query.strip()
    if not q:
        return []
    ql = q.lower()
    root = Path(root_dir).expanduser()
    if not root.exists():
        return []

    results: list[dict[str, Any]] = []
    seen: set[str] = set()

    def add_hit(path_str: str, is_dir: bool, snippet: str, score: int) -> None:
        if path_str in seen:
            return
        seen.add(path_str)
        p = Path(path_str)
        sz, mt = safe_stat(p)
        results.append({
            "path": path_str,
            "isDir": is_dir,
            "snippet": snippet[:160],
            "size": sz,
            "mtime": mt,
            "score": score,
        })

    # 1. Fast filename/folder scan (prioritizes Desktop, Documents, Downloads, Notes, Projects)
    priority_roots = [
        root / name for name in ("Documents", "Desktop", "Downloads", "Pictures", "Notes", "Projects", "src")
        if (root / name).is_dir()
    ]
    scan_roots = priority_roots if priority_roots else [root]

    for base in scan_roots:
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in SKIP_DIRS]
            rel_depth = len(Path(dirpath).relative_to(base).parts)
            if rel_depth > 4:
                dirnames[:] = []
                continue
            for d in dirnames:
                if ql in d.lower():
                    score = 100 if d.lower().startswith(ql) else 80
                    add_hit(os.path.join(dirpath, d), True, "", score)
            for fn in filenames:
                if fn.startswith("."):
                    continue
                if ql in fn.lower():
                    score = 95 if fn.lower().startswith(ql) else 75
                    add_hit(os.path.join(dirpath, fn), False, "", score)
            if len(results) >= limit * 2:
                break

    # 2. Full-text content search via ripgrep (when installed and query >= 3 chars)
    rg = shutil.which("rg")
    if rg and len(q) >= 3 and len(results) < limit:
        text_roots = [str(p) for p in scan_roots if p.is_dir()]
        if text_roots:
            cmd = [
                rg, "--no-heading", "--with-filename", "--line-number", "--ignore-case",
                "--max-count", "1", "--max-filesize", "512K", "--max-depth", "4",
                "--fixed-strings", "--", q,
            ] + text_roots
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=2.0, check=False)
                for line in proc.stdout.splitlines():
                    parts = line.split(":", 2)
                    if len(parts) < 3:
                        continue
                    fpath, lineno, text_hit = parts[0], parts[1], parts[2].strip()
                    add_hit(fpath, False, f"L{lineno}: {text_hit}", 60)
                    if len(results) >= limit * 2:
                        break
            except Exception:
                pass

    results.sort(key=lambda r: (-int(r["score"]), -float(r["mtime"])))
    return results[:limit]


def read_preview(path_str: str, max_chars: int = 2400) -> dict[str, Any]:
    p = Path(path_str).expanduser()
    if not p.exists():
        return {"ok": False, "error": "missing"}
    sz, mt = safe_stat(p)
    if p.is_dir():
        try:
            entries = sorted(e.name for e in p.iterdir() if not e.name.startswith("."))[:16]
        except OSError:
            entries = []
        return {"ok": True, "kind": "dir", "size": sz, "mtime": mt, "text": "\n".join(entries), "count": len(entries)}

    ext = p.suffix.lower()
    if ext == ".pdf":
        pdftotext = shutil.which("pdftotext")
        if pdftotext:
            try:
                proc = subprocess.run([pdftotext, "-f", "1", "-l", "2", str(p), "-"], capture_output=True, text=True, timeout=2.0, check=False)
                return {"ok": True, "kind": "pdf", "size": sz, "mtime": mt, "text": proc.stdout[:max_chars].strip()}
            except Exception:
                pass
        return {"ok": True, "kind": "pdf", "size": sz, "mtime": mt, "text": ""}

    if ext in TEXT_EXTS or sz <= 65536:
        try:
            raw = p.read_bytes()[: max_chars * 2]
            if b"\x00" not in raw:
                return {"ok": True, "kind": "text", "size": sz, "mtime": mt, "text": raw.decode("utf-8", errors="replace")[:max_chars]}
        except OSError:
            pass
    return {"ok": True, "kind": "file", "size": sz, "mtime": mt, "text": ""}


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "search":
        root_dir = argv[3] if len(argv) >= 4 else os.path.expanduser("~")
        sys.stdout.write(json.dumps(search_files(argv[2], root_dir), separators=(",", ":")))
        return 0
    if len(argv) >= 3 and argv[1] == "preview":
        sys.stdout.write(json.dumps(read_preview(argv[2]), separators=(",", ":")))
        return 0
    sys.stdout.write("[]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
