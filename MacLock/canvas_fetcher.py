#!/usr/bin/env python3
"""
canvas_fetcher.py - Apple Music Motion Artwork & Spotify Canvas Fetcher
Tiered Sources:
1. Local cache (~/.cache/macshell/canvas/<id_or_name>.mp4)
2. Apple Music Motion Artwork (Priority 1: High fidelity desktop-optimized 1080p AVC1 SDR)
3. Spotify Canvas (Priority 2 fallback: Spclient canvaz-cache via Firefox sp_dc or public proxy)
4. Fallback: Returns success=False so LockScreen cleanly displays blurred album art.

Features:
- Automatic LRU cache pruning (max 20 videos / 100MB) to prevent disk bloat.
- Stream remuxing via ffmpeg to guarantee instantaneous 0-timestamp playback and looping.
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

# ═══════════════════════ SPOTIFY CANVAS ═══════════════════════

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

def get_spotify_track_id(expected_title=None):
    """Detect current Spotify track ID from playerctl if available and matching."""
    try:
        if expected_title:
            out_title = subprocess.run(
                ["playerctl", "-p", "spotify", "metadata", "xesam:title"],
                capture_output=True, text=True, timeout=1.0
            )
            if out_title.returncode == 0 and out_title.stdout:
                sp_title = out_title.stdout.strip().lower()
                exp = expected_title.strip().lower()
                if exp and exp not in sp_title and sp_title not in exp:
                    return ""
        out = subprocess.run(
            ["playerctl", "-p", "spotify", "metadata", "mpris:trackid"],
            capture_output=True, text=True, timeout=1.5
        )
        if out.returncode == 0 and out.stdout:
            tid = out.stdout.strip()
            m = re.search(r'[a-zA-Z0-9]{22}', tid)
            if m:
                return m.group(0)
    except Exception:
        pass
    return ""

def is_full_hd(video_path):
    """Check if video is already scaled to 1920x1080 Full HD."""
    try:
        out = subprocess.run([
            'ffprobe', '-v', 'error', '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height', '-of', 'csv=s=x:p=0',
            video_path
        ], capture_output=True, text=True, timeout=1.5)
        return out.returncode == 0 and '1920x1080' in out.stdout.strip()
    except Exception:
        return False

def scale_to_full_hd(src_video, dest_video):
    """
    Scale / crop video to pristine 1920x1080 Full HD (16:9) using high-quality
    Lanczos filtering and subtle unsharp enhancement so it renders 1:1 pixel-perfect
    on desktop screens without runtime bilinear scaling blur.
    """
    try:
        temp_out = dest_video + ".fhd_tmp.mp4"
        cmd = [
            'ffmpeg', '-y', '-loglevel', 'error',
            '-i', src_video,
            '-vf', 'scale=1920:1080:force_original_aspect_ratio=increase:flags=lanczos,crop=1920:1080,unsharp=5:5:0.5:5:5:0.0',
            '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '17',
            '-pix_fmt', 'yuv420p',
            temp_out
        ]
        res = subprocess.run(cmd, timeout=25)
        if res.returncode == 0 and os.path.exists(temp_out) and os.path.getsize(temp_out) > 10000:
            os.replace(temp_out, dest_video)
            return True
        if os.path.exists(temp_out):
            try: os.remove(temp_out)
            except Exception: pass
    except Exception:
        pass
    return False

def ensure_full_hd(video_path):
    """Ensure cached video is scaled to crisp Full HD 1080p."""
    if not os.path.exists(video_path) or os.path.getsize(video_path) < 10000:
        return False
    if is_full_hd(video_path):
        return True
    return scale_to_full_hd(video_path, video_path)

def download_video(url, target_path):
    temp_dl = target_path + ".dl.mp4"
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=15) as resp:
            content = resp.read()
            if len(content) > 1000:
                with open(temp_dl, 'wb') as f:
                    f.write(content)
                if not scale_to_full_hd(temp_dl, target_path):
                    os.replace(temp_dl, target_path)
                elif os.path.exists(temp_dl):
                    try: os.remove(temp_dl)
                    except Exception: pass
                mark_used(target_path)
                prune_cache()
                return True
    except Exception:
        pass
    if os.path.exists(temp_dl):
        try: os.remove(temp_dl)
        except Exception: pass
    return False

# ═══════════════════════ APPLE MUSIC MOTION ARTWORK ═══════════════════════

def clean_song_title(t):
    """Strip feat, remastered, version, deluxe tags to maximize iTunes search accuracy."""
    if not t:
        return ""
    clean = re.sub(r'[\(\[\{].*?[\)\]\}]', '', t).strip()
    clean = re.sub(r'\s*-\s*(remaster|live|acoustic|edit|version|radio|deluxe|bonus).*', '', clean, flags=re.IGNORECASE).strip()
    return clean or t

def fetch_apple_music_motion(artist, title, album, target_path):
    """
    Search Apple Music via iTunes Search API and scrape the album page
    for official motion artwork (tall portrait 3:4 or square 1:1 HLS stream).
    Downloads H.264 AVC1 SDR video, scales/crops to Full HD 1080p with Lanczos.
    """
    clean_t = clean_song_title(title)
    clean_a = clean_song_title(album)

    # 1. Primary queries: artist + title is vastly more specific than album!
    queries = []
    if artist and clean_t:
        queries.append(f"{artist} {clean_t}")
    if artist and title and title != clean_t:
        queries.append(f"{artist} {title}")
    if clean_t:
        queries.append(clean_t)
    if artist and clean_a:
        queries.append(f"{artist} {clean_a}")

    checked_urls = set()
    candidate_urls = []

    # Search default storefront, and regional storefront (vn) for regional releases
    for sf in ["", "vn"]:
        for q in queries:
            try:
                sf_param = f"&country={sf}" if sf else ""
                search_url = f"https://itunes.apple.com/search?term={urllib.parse.quote_plus(q)}&entity=song&limit=6{sf_param}"
                req = urllib.request.Request(search_url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(req, timeout=4) as r:
                    res = json.loads(r.read().decode())
                for item in res.get('results', []):
                    cu = item.get('collectionViewUrl')
                    if cu and cu not in checked_urls:
                        checked_urls.add(cu)
                        t_name = item.get('trackName', '').strip().lower()
                        exact = (t_name == title.strip().lower() or t_name == clean_t.strip().lower())
                        candidate_urls.append((exact, cu))
            except Exception:
                continue
            if any(c[0] for c in candidate_urls):
                break
        if any(c[0] for c in candidate_urls):
            break

    # If song search returned nothing, fallback to album search
    if not candidate_urls and artist and (clean_a or clean_t):
        try:
            album_q = f"{artist} {clean_a or clean_t}"
            search_url = f"https://itunes.apple.com/search?term={urllib.parse.quote_plus(album_q)}&entity=album&limit=3"
            req = urllib.request.Request(search_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=4) as r:
                res = json.loads(r.read().decode())
            for item in res.get('results', []):
                cu = item.get('collectionViewUrl')
                if cu and cu not in checked_urls:
                    checked_urls.add(cu)
                    candidate_urls.append((True, cu))
        except Exception:
            pass

    candidate_urls.sort(key=lambda x: x[0], reverse=True)

    master_m3u8 = None
    for _, cu in candidate_urls[:3]:
        try:
            req_page = urllib.request.Request(cu, headers={
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36'
            })
            with urllib.request.urlopen(req_page, timeout=6) as r:
                html = r.read().decode('utf-8', errors='ignore')

            # Prefer iPad tall motion artwork (3:4 ratio, 1080x1440 or 2048x2732 - wider & optimal for desktop)
            tall = re.search(r'\"motionDetailTall\":\s*\{.*?\"video\":\s*\"(https://mvod\.itunes\.apple\.com/[^\"]+\.m3u8)\"', html, re.DOTALL)
            square = re.search(r'\"motionDetailSquare\":\s*\{.*?\"video\":\s*\"(https://mvod\.itunes\.apple\.com/[^\"]+\.m3u8)\"', html, re.DOTALL)
            if tall:
                master_m3u8 = tall.group(1)
                break
            if square:
                master_m3u8 = square.group(1)
                break
            all_m = re.findall(r'https://mvod\.itunes\.apple\.com/[^\"\'\s]+\.m3u8', html)
            if all_m:
                master_m3u8 = all_m[0]
                break
        except Exception:
            continue

    if not master_m3u8:
        return False

    try:
        req_master = urllib.request.Request(master_m3u8, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req_master, timeout=5) as r:
            master_content = r.read().decode('utf-8')

        candidates = []
        for m in re.finditer(r'#EXT-X-STREAM-INF:([^\n]+)\n([^\n]+)', master_content):
            info, stream_url = m.group(1), m.group(2)
            if 'avc1' in info:  # Prefer standard H.264 SDR
                res_m = re.search(r'RESOLUTION=([0-9]+)x([0-9]+)', info)
                w, h = (int(res_m.group(1)), int(res_m.group(2))) if res_m else (0, 0)
                bw_m = re.search(r'AVERAGE-BANDWIDTH=([0-9]+)', info)
                bw = int(bw_m.group(1)) if bw_m else 0
                candidates.append((w, h, bw, stream_url))

        if not candidates:
            stream_matches = re.findall(r'https://[^\n\s]+\.m3u8', master_content)
            chosen_stream = stream_matches[0] if stream_matches else master_m3u8
        else:
            # Pick a stream close to iPad Full HD (~1440 height for 3:4 or ~1080 for 1:1)
            candidates.sort(key=lambda c: abs(c[1] - 1440))
            chosen_stream = candidates[0][3]

        req_var = urllib.request.Request(chosen_stream, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req_var, timeout=5) as r:
            var_content = r.read().decode('utf-8')

        map_m = re.search(r'#EXT-X-MAP:URI=\"([^\"]+)\"', var_content)
        temp_direct = target_path + ".dl.mp4"

        if map_m:
            mp4_url = urllib.parse.urljoin(chosen_stream, map_m.group(1))
            req_dl = urllib.request.Request(mp4_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req_dl, timeout=12) as resp:
                data = resp.read()
            if len(data) > 10000:
                with open(temp_direct, 'wb') as f:
                    f.write(data)
                # Scale / crop to true 1920x1080 Full HD with Lanczos filter and subtle unsharp
                if scale_to_full_hd(temp_direct, target_path):
                    if os.path.exists(temp_direct):
                        try: os.remove(temp_direct)
                        except Exception: pass
                    return True
                # Fallback to copy remux if scale failed
                subprocess.run([
                    'ffmpeg', '-y', '-loglevel', 'error',
                    '-i', temp_direct, '-c', 'copy', target_path
                ], timeout=10)
                if os.path.exists(temp_direct):
                    try: os.remove(temp_direct)
                    except Exception: pass
                return os.path.exists(target_path) and os.path.getsize(target_path) > 10000

        # Fallback to ffmpeg stream capture + Full HD scale
        temp_cap = target_path + ".cap.mp4"
        subprocess.run([
            'ffmpeg', '-y', '-loglevel', 'error',
            '-i', chosen_stream, '-c', 'copy', '-t', '30', temp_cap
        ], timeout=15)
        if os.path.exists(temp_cap) and os.path.getsize(temp_cap) > 10000:
            if scale_to_full_hd(temp_cap, target_path):
                if os.path.exists(temp_cap):
                    try: os.remove(temp_cap)
                    except Exception: pass
                return True
            os.replace(temp_cap, target_path)
            return True
        return os.path.exists(target_path) and os.path.getsize(target_path) > 10000

    except Exception:
        return False

# ═══════════════════════════ MAIN ═══════════════════════════

def main():
    # Args: title, artist, album, artUrl, optional_track_id
    title = sys.argv[1] if len(sys.argv) > 1 else ""
    artist = sys.argv[2] if len(sys.argv) > 2 else ""
    album = sys.argv[3] if len(sys.argv) > 3 else ""
    art_url = sys.argv[4] if len(sys.argv) > 4 else ""
    track_id = sys.argv[5] if len(sys.argv) > 5 else ""

    if not track_id:
        track_id = get_spotify_track_id(title)

    key_base = f"{artist} - {title}".strip(" -")
    if not key_base and not track_id:
        print(json.dumps({"success": False, "videoPath": "", "isOfficial": False, "source": "none"}))
        return

    sanitized_name = sanitize(key_base)
    name_path = os.path.join(CACHE_DIR, f"{sanitized_name}.mp4") if sanitized_name else ""

    # 1. Check local cache files for real Apple Music files (skip old Spotify symlinks)
    if name_path and os.path.exists(name_path) and not os.path.islink(name_path) and os.path.getsize(name_path) > 10000:
        ensure_full_hd(name_path)
        mark_used(name_path)
        print(json.dumps({"success": True, "videoPath": name_path, "isOfficial": True, "source": "cache"}))
        return

    # 2. Priority 1: Apple Music Motion Artwork (high resolution, optimal desktop aspect ratio)
    target_apple_path = os.path.join(CACHE_DIR, f"{sanitized_name or (track_id or 'apple_motion')}.mp4")
    # If an old symlink exists at target path, remove it so real Apple Music file can replace it
    if os.path.islink(target_apple_path):
        try: os.remove(target_apple_path)
        except Exception: pass

    if fetch_apple_music_motion(artist, title, album, target_apple_path):
        mark_used(target_apple_path)
        prune_cache()
        if track_id and not os.path.exists(os.path.join(CACHE_DIR, f"{track_id}.mp4")):
            try:
                os.symlink(target_apple_path, os.path.join(CACHE_DIR, f"{track_id}.mp4"))
            except Exception:
                pass
        print(json.dumps({"success": True, "videoPath": target_apple_path, "isOfficial": True, "source": "applemusic"}))
        return

    # 3. Priority 2: Apple Music not found -> Check existing Spotify cache
    if name_path and os.path.exists(name_path) and os.path.getsize(name_path) > 10000:
        ensure_full_hd(name_path)
        mark_used(name_path)
        print(json.dumps({"success": True, "videoPath": name_path, "isOfficial": True, "source": "spotify"}))
        return

    if track_id:
        id_path = os.path.join(CACHE_DIR, f"{track_id}.mp4")
        if os.path.exists(id_path) and os.path.getsize(id_path) > 10000:
            ensure_full_hd(id_path)
            mark_used(id_path)
            print(json.dumps({"success": True, "videoPath": id_path, "isOfficial": True, "source": "spotify"}))
            return

    # 3. Priority 2: Spotify Canvas (fallback if Apple Music motion artwork is not available)
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
            print(json.dumps({"success": True, "videoPath": save_path, "isOfficial": True, "source": "spotify"}))
            return

    # 4. Neither exists -> Fall back cleanly to blurred album art background
    print(json.dumps({"success": False, "videoPath": "", "isOfficial": False, "source": "none"}))

if __name__ == "__main__":
    main()
