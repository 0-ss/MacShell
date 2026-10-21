#!/usr/bin/env python3
"""
Spotify Canvas Fetcher for MacLock Animated Lock Screen
Downloads looping canvas video for supported Spotify music and caches in ~/.cache/maclock/canvas/
Outputs the local .mp4 path to stdout if found.
"""

import sys
import os
import re
import json
import urllib.parse
import urllib.request
import subprocess
import time

def get_track_id(raw):
    raw = raw.strip()
    # If format is spotify:track:XXX
    m = re.search(r'spotify:track:([a-zA-Z0-9]{22})', raw)
    if m:
        return m.group(1)
    # If standard 22-char base62
    if re.match(r'^[a-zA-Z0-9]{22}$', raw):
        return raw
    # If URL
    m = re.search(r'track/([a-zA-Z0-9]{22})', raw)   # open.spotify.com/track/ID and /com/spotify/track/ID
    if m:
        return m.group(1)
    return None

def discover_spotify_track_id():
    """Read Spotify's standard MPRIS URL if Quickshell exposed only a generic track ID."""
    try:
        players = subprocess.run(["playerctl", "-l"], capture_output=True, text=True, timeout=3, check=False)
        for player in players.stdout.splitlines():
            if "spotify" not in player.lower():
                continue
            result = subprocess.run(
                ["playerctl", "-p", player, "metadata", "xesam:url"],
                capture_output=True, text=True, timeout=3, check=False
            )
            track_id = get_track_id(result.stdout)
            if track_id:
                return track_id
    except (OSError, subprocess.SubprocessError):
        pass
    return None

def log_err(cache_dir, msg):
    """Keep the last failure reason in <cache>/last-error.log so a missing Canvas can be diagnosed."""
    try:
        os.makedirs(cache_dir, exist_ok=True)
        with open(os.path.join(cache_dir, "last-error.log"), "a", encoding="utf-8") as f:
            f.write(msg + "\n")
    except OSError:
        pass

def read_sp_dc():
    """Optional Spotify web-player cookie (sp_dc). Put it in ~/.config/maclock/sp_dc or $SP_DC."""
    v = os.environ.get("SP_DC", "").strip()
    if v:
        return v
    try:
        with open(os.path.expanduser("~/.config/maclock/sp_dc"), "r", encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""

def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)

def ld(tag, payload):
    """Length-delimited protobuf field (handles lengths above 127)."""
    return bytes([(tag << 3) | 2]) + varint(len(payload)) + payload

def get_token(cache_dir, ua):
    sp_dc = read_sp_dc()
    urls = ["https://open.spotify.com/get_access_token?reason=transport&productType=web_player"]
    for url in urls:
        hdr = {"User-Agent": ua, "App-Platform": "WebPlayer", "Accept": "application/json"}
        if sp_dc:
            hdr["Cookie"] = "sp_dc=" + sp_dc
        try:
            req = urllib.request.Request(url, headers=hdr)
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = json.loads(resp.read().decode("utf-8", "ignore"))
                if data.get("accessToken"):
                    return data["accessToken"]
                log_err(cache_dir, "token: no accessToken in response")
        except Exception as e:
            log_err(cache_dir, "token request failed: %r (sp_dc %s)" % (e, "set" if sp_dc else "not set"))
    return None

def fetch_canvas(track_id, cache_dir):
    os.makedirs(cache_dir, exist_ok=True)
    video_path = os.path.join(cache_dir, f"{track_id}.mp4")
    if os.path.exists(video_path) and os.path.getsize(video_path) > 1000:
        return video_path
    # tracks with no Canvas are remembered, so they are not asked for again every time
    miss = os.path.join(cache_dir, f"{track_id}.none")
    if os.path.exists(miss) and (time.time() - os.path.getmtime(miss)) < 7 * 86400:
        return None

    ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    token = get_token(cache_dir, ua)
    if not token:
        return None

    # EntityCanvazRequest { repeated Entity entities = 1 }  Entity { string entity_uri = 1 }
    entity = ld(1, f"spotify:track:{track_id}".encode("utf-8"))
    payload = ld(1, entity)
    hdr = {
        "User-Agent": "Spotify/8.9.0 Android/34 (Pixel 8)",
        "Content-Type": "application/x-protobuf",
        "Accept": "application/protobuf",
        "Authorization": f"Bearer {token}",
    }
    canvas_url = None
    try:
        req = urllib.request.Request("https://spclient.wg.spotify.com/canvaz-cache/v0/canvases",
                                     data=payload, headers=hdr, method="POST")
        with urllib.request.urlopen(req, timeout=8) as resp:
            body = resp.read()
        m = re.search(rb'https?://[a-zA-Z0-9\.\-\/_]+\.mp4', body)
        if m:
            canvas_url = m.group(0).decode("utf-8", "ignore")
        else:
            open(miss, "w").close()          # answered, but this track has no Canvas
            return None
    except Exception as e:
        log_err(cache_dir, "canvaz request failed: %r" % (e,))
        return None

    try:
        req_dl = urllib.request.Request(canvas_url, headers={"User-Agent": ua})
        with urllib.request.urlopen(req_dl, timeout=15) as resp:
            content = resp.read()
        if len(content) > 1000:
            tmp_path = video_path + ".tmp"
            with open(tmp_path, "wb") as f:
                f.write(content)
            os.replace(tmp_path, video_path)
            return video_path
    except Exception as e:
        log_err(cache_dir, "canvas download failed: %r" % (e,))
    return None

def main():
    if len(sys.argv) < 2:
        return

    raw = sys.argv[1].strip()
    track_id = get_track_id(raw)
    if not track_id:
        track_id = discover_spotify_track_id()
    cache_dir = sys.argv[2].strip() if len(sys.argv) > 2 else os.path.expanduser("~/.cache/maclock/canvas")

    if not track_id:
        return

    video_path = fetch_canvas(track_id, cache_dir)
    if video_path and os.path.exists(video_path):
        print(video_path)

if __name__ == "__main__":
    main()
