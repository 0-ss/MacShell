#!/usr/bin/env python3
"""Return synchronized lyrics from the optional syncedlyrics providers."""
import json
import sys


def main():
    if len(sys.argv) != 3 or not sys.argv[1].strip():
        return
    try:
        import syncedlyrics

        text = syncedlyrics.search(
            f"{sys.argv[2]} {sys.argv[1]}".strip(),
            synced_only=True,
            providers=["Musixmatch", "NetEase", "Megalobiz"],
        )
    except Exception:
        return
    if text:
        print(json.dumps({"syncedLyrics": text}))


if __name__ == "__main__":
    main()
