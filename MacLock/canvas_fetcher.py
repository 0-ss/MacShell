#!/usr/bin/env python3
"""
canvas_fetcher.py - Official Spotify Canvas / Custom Video Fetcher
Sources:
1. Local cache (~/.cache/macshell/canvas/<id_or_name>.mp4)
2. Spotify Canvas (spclient canvaz-cache via Firefox sp_dc cookie)
3. Public Spotify Canvas fallback
Features:
- Automatic LRU cache pruning (max 20 videos / 100MB) to prevent disk bloat.
- If no canvas video is found, returns success=False so LockScreen
  falls back cleanly to the blurred album artwork.
"""

import sys
import os
import re
import json
import sqlite3
import time
import glob
import hmac
import hashlib
import struct
import urllib.request
import urllib.parse
import subprocess

CACHE_DIR = os.path.expanduser("~/.cache/macshell/canvas")
os.makedirs(CACHE_DIR, exist_ok=True)

MAX_CACHE_FILES = 20  # Max 20 canvas videos
MAX_CACHE_BYTES = 100 * 1024 * 1024  # 100 MB max to prevent disk bloat

def prune_cache():
    """Keep the canvas cache lean and prevent disk bloating."""
    try:
        files = []
        for f in os.listdir(CACHE_DIR):
            if f.endswith(".mp4"):
                fp = os.path.join(CACHE_DIR, f)
                if os.path.isfile(fp) and not os.path.islink(fp):
                    files.append((fp, os.path.getmtime(fp), os.path.getsize(fp)))

        files.sort(key=lambda x: x[1])
        total_size = sum(x[2] for x in files)
        while len(files) > MAX_CACHE_FILES or total_size > MAX_CACHE_BYTES:
            oldest, _, sz = files.pop(0)
            try:
                os.remove(oldest)
                total_size -= sz
            except Exception:
                pass
    except Exception:
        pass

def mark_used(filepath):
    try:
        os.utime(filepath, None)
    except Exception:
        pass

def sanitize(name):
    return re.sub(r'[^\w\-_\. ]', '_', name or "").strip()

def get_firefox_sp_dc():
    patterns = [
        os.path.expanduser("~/.config/mozilla/firefox/*.default-release/cookies.sqlite"),
        os.path.expanduser("~/.config/mozilla/firefox/*.default/cookies.sqlite"),
        os.path.expanduser("~/.mozilla/firefox/*.default-release/cookies.sqlite"),
    ]
    for pat in patterns:
        for p in glob.glob(pat):
            try:
                conn = sqlite3.connect(f"file:{p}?immutable=1", uri=True)
                cursor = conn.cursor()
                cursor.execute('SELECT value FROM moz_cookies WHERE host LIKE "%spotify%" AND name = "sp_dc"')
                row = cursor.fetchone()
                if row and row[0]:
                    return row[0]
            except Exception:
                continue
    return None

def gen_totp(ts, key, period=30, digits=6):
    counter = int(ts // period)
    msg = struct.pack('>Q', counter)
    h = hmac.new(key, msg, hashlib.sha1).digest()
    offset = h[-1] & 0x0f
    code = (struct.unpack('>I', h[offset:offset+4])[0] & 0x7fffffff) % (10 ** digits)
    return f'{code:0{digits}d}'

def get_spotify_token(sp_dc):
    try:
        secrets_url = "https://raw.githubusercontent.com/xyloflake/spot-secrets-go/refs/heads/main/secrets/secretDict.json"
        req = urllib.request.Request(secrets_url, headers={'User-Agent': 'Mozilla/5.0'})
        secrets = json.loads(urllib.request.urlopen(req, timeout=5).read().decode())
        newest_ver = str(max([int(k) for k in secrets.keys()]))
        secret_data = secrets[newest_ver]
        mapped = [v ^ ((i % 33) + 9) for i, v in enumerate(secret_data)]
        key = ''.join(str(x) for x in mapped).encode('utf-8')

        local_time = time.time()
        totp_code = gen_totp(local_time, key)

        params = {
            'reason': 'init',
            'productType': 'mobile-web-player',
            'totp': totp_code,
            'totpVer': newest_ver,
            'totpServer': totp_code
        }
        url = 'https://open.spotify.com/api/token?' + urllib.parse.urlencode(params)
        req_token = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
            'Origin': 'https://open.spotify.com/',
            'Referer': 'https://open.spotify.com/',
            'Cookie': f'sp_dc={sp_dc}'
        })
        res = json.loads(urllib.request.urlopen(req_token, timeout=5).read().decode())
        return res.get('accessToken')
    except Exception:
        return None

def fetch_spotify_canvas_url(track_id, access_token):
    track_uri = f'spotify:track:{track_id}'
    uri_bytes = track_uri.encode('utf-8')
    track_msg = bytes([0x0a, len(uri_bytes)]) + uri_bytes
    req_msg = bytes([0x0a, len(track_msg)]) + track_msg

    req = urllib.request.Request(
        'https://spclient.wg.spotify.com/canvaz-cache/v0/canvases',
        data=req_msg,
        headers={
            'Accept': 'application/protobuf',
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Spotify/9.0.34.593 iOS/18.4 (iPhone15,3)',
            'Authorization': f'Bearer {access_token}'
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = resp.read()
            urls = re.findall(rb'https://[^\x00-\x1f\x7f-\xff]+\.mp4', data)
            if urls:
                return urls[0].decode('utf-8')
    except Exception:
        pass
    return None

def fetch_public_canvas_url(track_id):
    try:
        url = f'https://spotify-canva.vercel.app/api/canvas?trackId={track_id}'
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            canvases = data.get('canvasesList', [])
            if canvases and canvases[0].get('canvasUrl'):
                return canvases[0].get('canvasUrl')
    except Exception:
        pass
    return None

def download_video(url, target_path):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=15) as resp:
            content = resp.read()
            if len(content) > 1000:
                with open(target_path, 'wb') as f:
                    f.write(content)
                mark_used(target_path)
                prune_cache()
                return True
    except Exception:
        pass
    return False

def get_spotify_track_id():
    """Detect current Spotify track ID from playerctl if available."""
    try:
        out = subprocess.run(
            ["playerctl", "-p", "spotify", "metadata", "mpris:trackid"],
            capture_output=True, text=True, timeout=1.5
        )
        if out.returncode == 0 and out.stdout:
            tid = out.stdout.strip()
            # e.g. /com/spotify/track/3mECPHiXfJOcY9s5JTvLrW or spotify:track:...
            m = re.search(r'[a-zA-Z0-9]{22}', tid)
            if m:
                return m.group(0)
    except Exception:
        pass
    return ""

def main():
    # Args: title, artist, album, artUrl, optional_track_id
    title = sys.argv[1] if len(sys.argv) > 1 else ""
    artist = sys.argv[2] if len(sys.argv) > 2 else ""
    album = sys.argv[3] if len(sys.argv) > 3 else ""
    art_url = sys.argv[4] if len(sys.argv) > 4 else ""
    track_id = sys.argv[5] if len(sys.argv) > 5 else ""

    if not track_id:
        track_id = get_spotify_track_id()

    key_base = f"{artist} - {title}".strip(" -")
    if not key_base and not track_id:
        print(json.dumps({"success": False, "videoPath": "", "isOfficial": False}))
        return

    # 1. Check local cache files
    if track_id:
        id_path = os.path.join(CACHE_DIR, f"{track_id}.mp4")
        if os.path.exists(id_path) and os.path.getsize(id_path) > 1000:
            mark_used(id_path)
            print(json.dumps({"success": True, "videoPath": id_path, "isOfficial": True}))
            return

    sanitized_name = sanitize(key_base)
    name_path = os.path.join(CACHE_DIR, f"{sanitized_name}.mp4")
    if os.path.exists(name_path) and os.path.getsize(name_path) > 1000:
        mark_used(name_path)
        print(json.dumps({"success": True, "videoPath": name_path, "isOfficial": True}))
        return

    if title:
        title_path = os.path.join(CACHE_DIR, f"{sanitize(title)}.mp4")
        if os.path.exists(title_path) and os.path.getsize(title_path) > 1000:
            mark_used(title_path)
            print(json.dumps({"success": True, "videoPath": title_path, "isOfficial": True}))
            return

    # 2. Try Spotify Canvas API if track_id exists
    canvas_mp4_url = None
    if track_id:
        sp_dc = get_firefox_sp_dc()
        if sp_dc:
            token = get_spotify_token(sp_dc)
            if token:
                canvas_mp4_url = fetch_spotify_canvas_url(track_id, token)

        if not canvas_mp4_url:
            canvas_mp4_url = fetch_public_canvas_url(track_id)

    if canvas_mp4_url:
        save_path = os.path.join(CACHE_DIR, f"{track_id if track_id else sanitized_name}.mp4")
        if download_video(canvas_mp4_url, save_path):
            if sanitized_name and save_path != name_path:
                try:
                    if not os.path.exists(name_path):
                        os.symlink(save_path, name_path)
                except Exception:
                    pass
            print(json.dumps({"success": True, "videoPath": save_path, "isOfficial": True}))
            return

    print(json.dumps({"success": False, "videoPath": "", "isOfficial": False}))

if __name__ == "__main__":
    main()
