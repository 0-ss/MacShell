#!/usr/bin/env python3
"""
lyrics_fetcher.py - Multi-source lyrics fetcher for MacShell
Sources:
1. LRCLIB (Direct GET & Search)
2. syncedlyrics (Musixmatch, NetEase, Megalobiz, Genius)
3. NetEase direct API fallback
Caches lyrics locally in ~/.cache/macshell/lyrics/
Outputs JSON: { "syncedLyrics": "...", "plainLyrics": "..." }
"""

import sys
import os
import re
import json
import urllib.parse
import urllib.request

CACHE_DIR = os.path.expanduser("~/.cache/macshell/lyrics")
os.makedirs(CACHE_DIR, exist_ok=True)

def sanitize_filename(name):
    return re.sub(r'[^\w\-_\. ]', '_', name).strip()

def clean_title(title):
    if not title:
        return ""
    s = title.strip()
    # Remove (feat. ...), [feat. ...], (ft. ...), (with ...)
    s = re.sub(r'[\(\[](?:feat\.?|ft\.?|with|prod\.?)\s+[^\)\]]+[\)\]]', '', s, flags=re.I)
    # Remove tags like (Remastered 2021), [Official Audio], (Deluxe Edition), (Live at ...)
    s = re.sub(r'[\(\[](?:remaster(?:ed)?|deluxe|version|edition|official|audio|video|visualizer|live|acoustic|instrumental|bonus\s+track|mono|stereo|radio\s+edit)[^\)\]]*[\)\]]', '', s, flags=re.I)
    # Remove trailing " - Remastered...", " - Live...", " - Single", etc.
    s = re.sub(r'\s+-\s+(?:remaster(?:ed)?|live|single|deluxe|version|edition|official|audio|video|bonus|radio\s+edit).*$', '', s, flags=re.I)
    return s.strip()

def clean_artist(artist):
    if not artist:
        return ""
    # Split multiple artists: e.g. "The Weeknd, Daft Punk" -> "The Weeknd"
    parts = re.split(r'[,;/]|\s+(?:feat\.?|ft\.?|with|x|&)\s+', artist.strip(), flags=re.I)
    return parts[0].strip()

def fetch_json(url, timeout=5):
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "macshell-lyrics/1.0 (quickshell)"}
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status == 200:
                return json.loads(resp.read().decode('utf-8', errors='replace'))
    except Exception:
        pass
    return None

def try_lrclib(title, artist, album, duration):
    cl_title = clean_title(title)
    cl_artist = clean_artist(artist)
    
    # 1. Try LRCLIB exact get with clean title & artist (no album/duration to prevent 404 mismatches)
    if cl_title and cl_artist:
        params = {"track_name": cl_title, "artist_name": cl_artist}
        url = "https://lrclib.net/api/get?" + urllib.parse.urlencode(params)
        res = fetch_json(url, timeout=5)
        if res and (res.get("syncedLyrics") or res.get("plainLyrics")):
            return res

    # 2. Try LRCLIB exact get with raw title & artist
    if title and artist:
        params = {"track_name": title, "artist_name": artist}
        url = "https://lrclib.net/api/get?" + urllib.parse.urlencode(params)
        res = fetch_json(url, timeout=5)
        if res and (res.get("syncedLyrics") or res.get("plainLyrics")):
            return res

    # 3. Try LRCLIB search with clean artist + clean title
    q = f"{cl_artist} {cl_title}".strip()
    if q:
        url = "https://lrclib.net/api/search?" + urllib.parse.urlencode({"q": q})
        res = fetch_json(url, timeout=5)
        if isinstance(res, list) and len(res) > 0:
            for item in res:
                if item.get("syncedLyrics"):
                    return item
            return res[0]

    # 4. Try LRCLIB search with just title
    if cl_title:
        url = "https://lrclib.net/api/search?" + urllib.parse.urlencode({"q": cl_title})
        res = fetch_json(url, timeout=5)
        if isinstance(res, list) and len(res) > 0:
            for item in res:
                if item.get("syncedLyrics"):
                    return item
            return res[0]

    return None

def try_syncedlyrics(title, artist):
    try:
        import syncedlyrics
        cl_title = clean_title(title)
        cl_artist = clean_artist(artist)
        
        # Try clean artist + title
        query = f"{cl_artist} {cl_title}".strip()
        lrc = syncedlyrics.search(query, providers=["Musixmatch", "NetEase", "Lrclib", "Megalobiz"])
        if lrc:
            return {"syncedLyrics": lrc, "plainLyrics": ""}
        
        # Try raw title + artist
        query2 = f"{title} {artist}".strip()
        if query2 != query:
            lrc2 = syncedlyrics.search(query2, providers=["Musixmatch", "NetEase", "Lrclib", "Megalobiz"])
            if lrc2:
                return {"syncedLyrics": lrc2, "plainLyrics": ""}
    except Exception:
        pass
    return None

def get_lyrics(title, artist, album, duration):
    if not title:
        return {"error": "no title"}

    cache_key = sanitize_filename(f"{artist}_{title}".strip("_"))
    cache_file = os.path.join(CACHE_DIR, f"{cache_key}.json")
    
    # Check cache
    if os.path.exists(cache_file):
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                if data.get("syncedLyrics") or data.get("plainLyrics") or data.get("synced") or data.get("plain"):
                    synced = data.get("synced") or data.get("syncedLyrics") or ""
                    plain = data.get("plain") or data.get("plainLyrics") or ""
                    return {
                        "synced": synced,
                        "syncedLyrics": synced,
                        "plain": plain,
                        "plainLyrics": plain
                    }
        except Exception:
            pass

    # Step 1: Try LRCLIB for synced lyrics
    res = try_lrclib(title, artist, album, duration)
    if res and res.get("syncedLyrics"):
        s = res.get("syncedLyrics") or ""
        p = res.get("plainLyrics") or ""
        out = {
            "synced": s,
            "syncedLyrics": s,
            "plain": p,
            "plainLyrics": p
        }
        try:
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump(out, f, ensure_ascii=False)
        except Exception:
            pass
        return out

    # Step 2: Try syncedlyrics (Musixmatch / NetEase / Megalobiz)
    res_sl = try_syncedlyrics(title, artist)
    if res_sl and res_sl.get("syncedLyrics"):
        s = res_sl.get("syncedLyrics") or ""
        out = {
            "synced": s,
            "syncedLyrics": s,
            "plain": "",
            "plainLyrics": ""
        }
        try:
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump(out, f, ensure_ascii=False)
        except Exception:
            pass
        return out

    # Step 3: Fallback to LRCLIB plain lyrics if available
    if res and res.get("plainLyrics"):
        p = res.get("plainLyrics") or ""
        out = {
            "synced": "",
            "syncedLyrics": "",
            "plain": p,
            "plainLyrics": p
        }
        try:
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump(out, f, ensure_ascii=False)
        except Exception:
            pass
        return out

    return {"error": "not found"}

def get_current_line(title, artist, pos_sec):
    if not title:
        return ""
    try:
        lyrics_data = get_lyrics(title, artist, "", "0")
    except Exception:
        return ""
    synced = lyrics_data.get("synced") or lyrics_data.get("syncedLyrics") or ""
    if not synced:
        plain = lyrics_data.get("plain") or lyrics_data.get("plainLyrics") or ""
        if plain:
            for l in plain.splitlines():
                if l.strip():
                    return l.strip()
        return ""
    cur_line = ""
    try:
        target_pos = float(pos_sec) + 0.35
    except Exception:
        target_pos = 0.35
    time_re = re.compile(r'\[(\d+):(\d+(?:\.\d+)?)\]')
    has_started = False
    for raw_line in synced.splitlines():
        m = time_re.search(raw_line)
        if m:
            t = int(m.group(1)) * 60 + float(m.group(2))
            text = time_re.sub('', raw_line).strip()
            # remove word-level tags
            text = re.sub(r'<[^>]*>', '', text).strip()
            if t <= target_pos:
                has_started = True
                if text:
                    cur_line = text
            else:
                break
    if not has_started:
        return "♪  ♪  ♪"
    return cur_line or "♪  ♪  ♪"


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--current":
        title = sys.argv[2] if len(sys.argv) > 2 else ""
        artist = sys.argv[3] if len(sys.argv) > 3 else ""
        pos = sys.argv[4] if len(sys.argv) > 4 else "0"
        print(get_current_line(title, artist, pos))
        return

    title = sys.argv[1] if len(sys.argv) > 1 else ""
    artist = sys.argv[2] if len(sys.argv) > 2 else ""
    album = sys.argv[3] if len(sys.argv) > 3 else ""
    duration = sys.argv[4] if len(sys.argv) > 4 else "0"

    result = get_lyrics(title, artist, album, duration)
    print(json.dumps(result, ensure_ascii=False))

if __name__ == "__main__":
    main()
