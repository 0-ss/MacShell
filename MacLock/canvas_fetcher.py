#!/usr/bin/env python3
"""
canvas_fetcher.py - Ultra-fast Apple Music Motion Artwork & Spotify Canvas Fetcher
Tiered Sources:
1. Local cache (~/.cache/macshell/canvas/<id_or_name>.mp4) -> ~0.001s instant hit
2. Apple Music Motion Artwork (Priority 1: High fidelity tall 3:4 / square 1:1 via Apple AMP API)
3. Spotify Canvas (Priority 2 fallback: Spclient canvaz-cache via Firefox sp_dc or public proxy)
4. Clean Fallback: Returns success=False so LockScreen cleanly displays blurred album art.

High Performance Features:
- Direct Apple AMP API queries with cached Bearer JWT (avoids heavy unauthenticated HTML scraping).
- Zero CPU software re-encoding: native GPU scaling via Qt Quick's VideoOutput.PreserveAspectCrop.
- Stream remuxing via ffmpeg stream copy (-c copy -movflags +faststart) for instant seek & looping.
- Optimal HLS variant selection (avoids bloated 20-30MB bitrates while preserving crisp 1080p visual fidelity).
- Automatic LRU cache pruning (max 25 videos / 120MB) to prevent disk bloat.
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
import base64
import urllib.request
import urllib.parse
import subprocess

CACHE_DIR = os.path.expanduser("~/.cache/macshell/canvas")
ART_CACHE_DIR = os.path.expanduser("~/.cache/macshell/art")
APPLE_TOKEN_CACHE = os.path.expanduser("~/.cache/macshell/apple_token.json")
ART_MAPPING_FILE = os.path.join(CACHE_DIR, "art_mapping.json")
os.makedirs(CACHE_DIR, exist_ok=True)
os.makedirs(ART_CACHE_DIR, exist_ok=True)

MAX_CACHE_FILES = 12  # Generous cache (holds full albums & recent favorites)
MAX_CACHE_BYTES = 120 * 1024 * 1024  # 120 MB max (fast, reusable, instant)

FALLBACK_APPLE_TOKEN = (
    "eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IldlYlBsYXlLaWQifQ."
    "eyJpc3MiOiJBTVBXZWJQbGF5IiwiaWF0IjoxNzkxOTAzMTk0LCJleHAiOjE3OTc5NTExOTQs"
    "InJvb3RfaHR0cHNfb3JpZ2luIjpbImFwcGxlLmNvbSJdfQ."
    "3x-70iwl8xfaZvlRoH-4_Z_kBmfaFrEYW6Pqa9u0vJKZHwq1iYdw_LJs1LA8mxQpyxeHcmuHPXdq6pjBO41_kA"
)

def load_art_mapping():
    if os.path.exists(ART_MAPPING_FILE):
        try:
            with open(ART_MAPPING_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_art_mapping(mapping):
    try:
        with open(ART_MAPPING_FILE, "w", encoding="utf-8") as f:
            json.dump(mapping, f, indent=2)
    except Exception:
        pass

def get_art_hash(art_url):
    if not art_url:
        return ""
    # Extract clean art identifier from Spotify URL if available
    # e.g., https://i.scdn.co/image/ab67616d0000b273bc18bdade69ec5ef0bb25b17 -> ab67616d0000b273bc18bdade69ec5ef0bb25b17
    parts = art_url.strip().split("/")[-1].split("?")[0]
    if len(parts) >= 20 and re.match(r'^[a-zA-Z0-9_\-]+$', parts):
        return parts.lower()
    return hashlib.md5(art_url.strip().encode("utf-8")).hexdigest()

def prune_cache():
    """Keep the canvas cache lean and prevent disk bloating."""
    try:
        files = []
        for f in os.listdir(CACHE_DIR):
            fp = os.path.join(CACHE_DIR, f)
            # Remove broken symlinks
            if os.path.islink(fp) and not os.path.exists(fp):
                try:
                    os.remove(fp)
                except Exception:
                    pass
                continue
            if f.endswith(".mp4") and os.path.isfile(fp) and not os.path.islink(fp):
                try:
                    files.append((fp, os.path.getmtime(fp), os.path.getsize(fp)))
                except Exception:
                    pass

        files.sort(key=lambda x: x[1])
        total_size = sum(x[2] for x in files)
        while len(files) > MAX_CACHE_FILES or total_size > MAX_CACHE_BYTES:
            oldest, _, sz = files.pop(0)
            try:
                os.remove(oldest)
                total_size -= sz
            except Exception:
                pass

        # Cleanup any newly orphaned symlinks
        for f in os.listdir(CACHE_DIR):
            fp = os.path.join(CACHE_DIR, f)
            if os.path.islink(fp) and not os.path.exists(fp):
                try:
                    os.remove(fp)
                except Exception:
                    pass

        # Cleanup art mapping entries whose target video no longer exists
        mapping = load_art_mapping()
        changed = False
        valid_mapping = {}
        for k, v in mapping.items():
            if isinstance(v, dict):
                v_path = v.get("videoPath", "")
            else:
                v_path = str(v)
            if os.path.exists(v_path) and os.path.getsize(v_path) > 10000:
                valid_mapping[k] = v
            else:
                changed = True
        if changed:
            save_art_mapping(valid_mapping)
    except Exception:
        pass

def mark_used(filepath):
    try:
        os.utime(filepath, None)
    except Exception:
        pass

def sanitize(name):
    return re.sub(r'[^\w\-_\. ]', '_', name or "").strip()

# ═══════════════════════ STREAM REMUXING ═══════════════════════

def fast_remux(src_video, dest_video):
    """
    Fast remux stream using ffmpeg stream copy (-c copy) and -movflags +faststart.
    Guarantees instant seek, 0-timestamp, and smooth loop without CPU re-encoding.
    """
    try:
        temp_out = dest_video + ".remux.mp4"
        cmd = [
            'ffmpeg', '-y', '-loglevel', 'error',
            '-i', src_video,
            '-c', 'copy',
            '-movflags', '+faststart',
            temp_out
        ]
        res = subprocess.run(cmd, timeout=8)
        if res.returncode == 0 and os.path.exists(temp_out) and os.path.getsize(temp_out) > 5000:
            os.replace(temp_out, dest_video)
            return True
        if os.path.exists(temp_out):
            try: os.remove(temp_out)
            except Exception: pass
    except Exception:
        pass
    if src_video != dest_video and os.path.exists(src_video):
        try:
            os.replace(src_video, dest_video)
            return True
        except Exception:
            pass
    return False

def ensure_full_hd(video_path):
    """Ensure video exists and is non-empty without expensive CPU re-encoding."""
    return os.path.exists(video_path) and os.path.getsize(video_path) > 10000

def download_video(url, target_path):
    """Download video directly and fast-remux with zero transcoding overhead."""
    temp_dl = target_path + ".dl.mp4"
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=12) as resp:
            content = resp.read()
            if len(content) > 1000:
                with open(temp_dl, 'wb') as f:
                    f.write(content)
                if not fast_remux(temp_dl, target_path):
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
        secrets = json.loads(urllib.request.urlopen(req, timeout=4).read().decode())
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
        res = json.loads(urllib.request.urlopen(req_token, timeout=4).read().decode())
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
        with urllib.request.urlopen(req, timeout=5) as resp:
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
        with urllib.request.urlopen(req, timeout=4) as resp:
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
                capture_output=True, text=True, timeout=0.8
            )
            if out_title.returncode == 0 and out_title.stdout:
                sp_title = out_title.stdout.strip().lower()
                exp = expected_title.strip().lower()
                if exp and exp not in sp_title and sp_title not in exp:
                    return ""
        out = subprocess.run(
            ["playerctl", "-p", "spotify", "metadata", "mpris:trackid"],
            capture_output=True, text=True, timeout=0.8
        )
        if out.returncode == 0 and out.stdout:
            tid = out.stdout.strip()
            m = re.search(r'[a-zA-Z0-9]{22}', tid)
            if m:
                return m.group(0)
    except Exception:
        pass
    return ""

# ═══════════════════════ APPLE MUSIC MOTION ARTWORK ═══════════════════════

def get_jwt_exp(token):
    try:
        parts = token.split('.')
        if len(parts) >= 2:
            payload = parts[1] + '=' * (-len(parts[1]) % 4)
            data = json.loads(base64.urlsafe_b64decode(payload))
            return int(data.get('exp', 0))
    except Exception:
        pass
    return 0

def get_apple_bearer_token():
    """
    Get Apple Music Bearer Developer Token.
    1. Checks disk cache (~/.cache/macshell/apple_token.json) for 0ms latency.
    2. Uses hardcoded fallback token (valid through late 2026).
    3. Auto-refreshes from music.apple.com web assets if expired.
    """
    now = time.time()
    if os.path.exists(APPLE_TOKEN_CACHE):
        try:
            with open(APPLE_TOKEN_CACHE, 'r', encoding='utf-8') as f:
                d = json.load(f)
            tok = d.get('token', '')
            exp = d.get('exp', 0)
            if tok and exp > now + 3600:
                return tok
        except Exception:
            pass

    fb_exp = get_jwt_exp(FALLBACK_APPLE_TOKEN)
    if fb_exp > now + 3600:
        try:
            os.makedirs(os.path.dirname(APPLE_TOKEN_CACHE), exist_ok=True)
            with open(APPLE_TOKEN_CACHE, 'w', encoding='utf-8') as f:
                json.dump({'token': FALLBACK_APPLE_TOKEN, 'exp': fb_exp}, f)
        except Exception:
            pass
        return FALLBACK_APPLE_TOKEN

    try:
        req = urllib.request.Request('https://music.apple.com', headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=5) as r:
            html = r.read().decode('utf-8', errors='ignore')
        js_assets = re.findall(r'(/assets/[^\"\']+\.js)', html)
        js_assets.sort(key=lambda x: 0 if 'index' in x else 1)
        jwt_regex = re.compile(r'[\"\'](eyJ[A-Za-z0-9-_=]+\.[A-Za-z0-9-_=]+\.[A-Za-z0-9-_=]+)[\"\']')
        for p in js_assets[:3]:
            try:
                js_url = f'https://music.apple.com{p}'
                req_js = urllib.request.Request(js_url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(req_js, timeout=5) as r_js:
                    js_text = r_js.read().decode('utf-8', errors='ignore')
                m = jwt_regex.search(js_text)
                if m:
                    new_tok = m.group(1)
                    new_exp = get_jwt_exp(new_tok)
                    if new_tok and new_exp > now:
                        try:
                            with open(APPLE_TOKEN_CACHE, 'w', encoding='utf-8') as f:
                                json.dump({'token': new_tok, 'exp': new_exp}, f)
                        except Exception:
                            pass
                        return new_tok
            except Exception:
                continue
    except Exception:
        pass
    return FALLBACK_APPLE_TOKEN

def clean_song_title(t):
    """Strip feat, remastered, version, deluxe tags to maximize search accuracy."""
    if not t:
        return ""
    clean = re.sub(r'[\(\[\{].*?[\)\]\}]', '', t).strip()
    clean = re.sub(r'\s*-\s*(remaster|live|acoustic|edit|version|radio|deluxe|bonus).*', '', clean, flags=re.IGNORECASE).strip()
    return clean or t

def select_best_hls_stream(master_content, default_url):
    """
    Select optimal AVC1 (H.264 SDR) stream:
    Targets crisp ~1080p resolution while keeping bandwidth moderate (<= 4.5 Mbps)
    for instantaneous stream download and seamless hardware playback.
    """
    candidates = []
    for m in re.finditer(r'#EXT-X-STREAM-INF:([^\n]+)\n([^\n]+)', master_content):
        info, stream_url = m.group(1), m.group(2)
        if 'avc1' in info:
            res_m = re.search(r'RESOLUTION=([0-9]+)x([0-9]+)', info)
            w, h = (int(res_m.group(1)), int(res_m.group(2))) if res_m else (0, 0)
            bw_m = re.search(r'AVERAGE-BANDWIDTH=([0-9]+)', info) or re.search(r'BANDWIDTH=([0-9]+)', info)
            bw = int(bw_m.group(1)) if bw_m else 0
            candidates.append((w, h, bw, stream_url))

    if not candidates:
        all_streams = re.findall(r'https://[^\n\s]+\.m3u8', master_content)
        return all_streams[0] if all_streams else default_url

    def score(c):
        w, h, bw, _ = c
        height_diff = abs(h - 1080)
        bw_penalty = max(0, bw - 4500000) / 10000
        res_penalty = 1000 if h < 600 else 0
        return height_diff + bw_penalty + res_penalty

    candidates.sort(key=score)
    return candidates[0][3]

def fetch_apple_music_motion(artist, title, album, target_path):
    """
    Search Apple Music via iTunes Search API and fetch official motion artwork
    (portrait 3:4 tall or 1:1 square) via Apple AMP API using Bearer Token.
    Streams are downloaded and remuxed at maximum speed with zero CPU transcoding.
    """
    clean_t = clean_song_title(title)
    clean_a = clean_song_title(album)

    # 1. Targeted search query: artist + title is fastest and most accurate
    queries = []
    if artist and clean_t:
        queries.append(f"{artist} {clean_t}")
    if clean_t:
        queries.append(clean_t)
    if artist and clean_a and clean_a != clean_t:
        queries.append(f"{artist} {clean_a}")

    candidate_url = None
    for q in queries:
        try:
            search_url = f"https://itunes.apple.com/search?term={urllib.parse.quote_plus(q)}&entity=song&limit=5"
            req = urllib.request.Request(search_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=3.5) as r:
                res = json.loads(r.read().decode())
            for item in res.get('results', []):
                cu = item.get('collectionViewUrl')
                if cu:
                    t_name = item.get('trackName', '').strip().lower()
                    if t_name == title.strip().lower() or t_name == clean_t.strip().lower():
                        candidate_url = cu
                        break
                    if not candidate_url:
                        candidate_url = cu
            if candidate_url:
                break
        except Exception:
            continue

    if not candidate_url:
        return False, []

    m = re.search(r'music\.apple\.com/(?:([a-z]{2})/)?album/(?:[^/]+/)?(\d+)', candidate_url)
    if not m:
        return False, []
    sf = m.group(1) or "us"
    aid = m.group(2)

    # 2. Query Apple AMP API with cached Bearer Token
    token = get_apple_bearer_token()
    api_url = f"https://amp-api.music.apple.com/v1/catalog/{sf}/albums/{aid}?extend=editorialVideo&platform=web"
    master_m3u8 = None
    try:
        req_api = urllib.request.Request(api_url, headers={
            'Authorization': f'Bearer {token}',
            'Origin': 'https://music.apple.com',
            'User-Agent': 'Mozilla/5.0'
        })
        with urllib.request.urlopen(req_api, timeout=4) as r_api:
            api_data = json.loads(r_api.read().decode())
        item = api_data.get('data', [{}])[0]
        ev = item.get('attributes', {}).get('editorialVideo', {})
        tall = ev.get('motionDetailTall') or ev.get('motionTallVideo3x4')
        square = ev.get('motionDetailSquare') or ev.get('motionSquareVideo1x1')
        master_m3u8 = (tall or square or {}).get('video')
        album_tracks = item.get('relationships', {}).get('tracks', {}).get('data', [])
    except Exception:
        return False, []

    if not master_m3u8:
        return False, []

    # Extract all track titles from this album to associate with this video
    sibling_titles = []
    for tr in album_tracks:
        t_attrs = tr.get('attributes', {})
        t_name = t_attrs.get('name')
        if t_name:
            sibling_titles.append(t_name)

    # 3. Stream download and remux
    try:
        req_master = urllib.request.Request(master_m3u8, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req_master, timeout=4) as r:
            master_content = r.read().decode('utf-8')

        chosen_stream = select_best_hls_stream(master_content, master_m3u8)

        req_var = urllib.request.Request(chosen_stream, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req_var, timeout=4) as r:
            var_content = r.read().decode('utf-8')

        map_m = re.search(r'#EXT-X-MAP:URI=\"([^\"]+)\"', var_content)
        temp_raw = target_path + ".raw.mp4"

        if map_m:
            mp4_url = urllib.parse.urljoin(chosen_stream, map_m.group(1))
            req_dl = urllib.request.Request(mp4_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req_dl, timeout=12) as resp:
                data = resp.read()
            if len(data) > 10000:
                with open(temp_raw, 'wb') as f:
                    f.write(data)
                if not fast_remux(temp_raw, target_path):
                    os.replace(temp_raw, target_path)
                elif os.path.exists(temp_raw):
                    try: os.remove(temp_raw)
                    except Exception: pass
                ok = os.path.exists(target_path) and os.path.getsize(target_path) > 10000
                return ok, sibling_titles

        # Fallback: ffmpeg stream remux
        subprocess.run([
            'ffmpeg', '-y', '-loglevel', 'error',
            '-i', chosen_stream, '-c', 'copy', '-movflags', '+faststart', '-t', '30',
            target_path
        ], timeout=12)
        ok = os.path.exists(target_path) and os.path.getsize(target_path) > 10000
        return ok, sibling_titles

    except Exception:
        return False, []

# ═══════════════════════════ MAIN ═══════════════════════════

def fetch_local_art(art_url, artist, title):
    """
    Safely download album art locally using Python so Qt Quick's Image
    never invokes QNetworkAccessManager/OpenSSL on background threads,
    completely eliminating SIGSEGV in X509_STORE_add_cert / libcrypto.
    """
    if not art_url:
        return ""
    if art_url.startswith("file://"):
        return art_url.replace("file://", "")
    try:
        h = hashlib.md5((art_url or f"{artist}_{title}").encode()).hexdigest()
        dest = os.path.join(ART_CACHE_DIR, f"{h}.jpg")
        if os.path.exists(dest) and os.path.getsize(dest) > 1000:
            return dest
        req = urllib.request.Request(art_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=3.5) as r:
            data = r.read()
        if len(data) > 1000:
            with open(dest, "wb") as f:
                f.write(data)
            return dest
    except Exception:
        pass
    return ""

def get_configured_mode(explicit_mode=None):
    if explicit_mode:
        return explicit_mode.lower()
    env_mode = os.environ.get("MACLOCK_CANVAS_MODE") or os.environ.get("MACSHELL_CANVAS_MODE")
    if env_mode:
        return env_mode.lower()
    for p in ("~/.config/maclock/settings.json", "~/.config/macbar/settings.json"):
        try:
            cfg_path = os.path.expanduser(p)
            if os.path.exists(cfg_path):
                with open(cfg_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if "canvasMode" in data and data["canvasMode"]:
                        return str(data["canvasMode"]).lower()
        except Exception:
            pass
    return "both"

def main():
    args = []
    cli_mode = None
    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg in ("--mode", "-m") and i + 1 < len(sys.argv):
            cli_mode = sys.argv[i + 1].lower()
            i += 2
        elif arg.startswith("--mode="):
            cli_mode = arg.split("=", 1)[1].lower()
            i += 1
        else:
            args.append(arg)
            i += 1

    title = args[0] if len(args) > 0 else ""
    artist = args[1] if len(args) > 1 else ""
    album = args[2] if len(args) > 2 else ""
    art_url = args[3] if len(args) > 3 else ""
    track_id = args[4] if len(args) > 4 else ""

    mode = get_configured_mode(cli_mode)

    # Prune cache right away to keep disk space under 20MB
    prune_cache()

    # If canvas is turned off, stop cleanly
    if mode in ("off", "none", "false", "disabled", "0"):
        local_art = fetch_local_art(art_url, artist, title)
        if local_art:
            print(json.dumps({"type": "art", "localArt": local_art}), flush=True)
        print(json.dumps({"type": "video", "success": False, "videoPath": "", "isOfficial": False, "source": "off"}), flush=True)
        return

    if not track_id and mode != "applemusic":
        track_id = get_spotify_track_id(title)

    key_base = f"{artist} - {title}".strip(" -")
    if not key_base and not track_id:
        local_art = fetch_local_art(art_url, artist, title)
        if local_art:
            print(json.dumps({"type": "art", "localArt": local_art}), flush=True)
        print(json.dumps({"type": "video", "success": False, "videoPath": "", "isOfficial": False, "source": "none"}), flush=True)
        return

    sanitized_name = sanitize(key_base)
    name_path = os.path.join(CACHE_DIR, f"{sanitized_name}.mp4") if sanitized_name else ""
    id_path = os.path.join(CACHE_DIR, f"{track_id}.mp4") if track_id else ""

    allow_apple = mode in ("both", "auto", "applemusic", "apple", "all")
    allow_spotify = mode in ("both", "auto", "spotify", "all")

    # 1. Instant Cache Hit Check (< 0.001s response time)
    # Check art_hash mapping first (shared album artwork / canvas reuse)
    art_hash = get_art_hash(art_url)
    if art_hash:
        art_map = load_art_mapping()
        if art_hash in art_map:
            cached_info = art_map[art_hash]
            mapped_video = cached_info.get("videoPath", "") if isinstance(cached_info, dict) else str(cached_info)
            mapped_source = cached_info.get("source", "applemusic") if isinstance(cached_info, dict) else "applemusic"
            mapped_official = cached_info.get("isOfficial", True) if isinstance(cached_info, dict) else True
            if mapped_video and os.path.exists(mapped_video) and os.path.getsize(mapped_video) > 10000:
                mark_used(mapped_video)
                print(json.dumps({"type": "video", "success": True, "videoPath": mapped_video, "isOfficial": mapped_official, "source": mapped_source}), flush=True)
                local_art = fetch_local_art(art_url, artist, title)
                if local_art:
                    print(json.dumps({"type": "art", "localArt": local_art}), flush=True)
                return

    # Check Apple Music cache hit
    if allow_apple and name_path and os.path.exists(name_path) and not os.path.islink(name_path) and os.path.getsize(name_path) > 10000:
        mark_used(name_path)
        if art_hash:
            art_map = load_art_mapping()
            art_map[art_hash] = {"videoPath": name_path, "source": "applemusic", "isOfficial": True}
            save_art_mapping(art_map)
        print(json.dumps({"type": "video", "success": True, "videoPath": name_path, "isOfficial": True, "source": "applemusic"}), flush=True)
        local_art = fetch_local_art(art_url, artist, title)
        if local_art:
            print(json.dumps({"type": "art", "localArt": local_art}), flush=True)
        return

    # Check Spotify cache hit
    if allow_spotify:
        hit_path = None
        if id_path and os.path.exists(id_path) and os.path.getsize(id_path) > 10000:
            hit_path = id_path
        elif name_path and os.path.exists(name_path) and os.path.getsize(name_path) > 10000:
            hit_path = name_path
        if hit_path:
            mark_used(hit_path)
            if art_hash:
                art_map = load_art_mapping()
                art_map[art_hash] = {"videoPath": hit_path, "source": "spotify", "isOfficial": True}
                save_art_mapping(art_map)
            print(json.dumps({"type": "video", "success": True, "videoPath": hit_path, "isOfficial": True, "source": "spotify"}), flush=True)
            local_art = fetch_local_art(art_url, artist, title)
            if local_art:
                print(json.dumps({"type": "art", "localArt": local_art}), flush=True)
            return

    # 2. Not in cache yet: immediately emit local art so QML displays cover art & blurred background in < 0.05s
    local_art = fetch_local_art(art_url, artist, title)
    if local_art:
        print(json.dumps({"type": "art", "localArt": local_art}), flush=True)

    # 3. Apple Music Motion Artwork
    if allow_apple:
        target_apple_path = os.path.join(CACHE_DIR, f"{sanitized_name or (track_id or 'apple_motion')}.mp4")
        if os.path.islink(target_apple_path):
            try: os.remove(target_apple_path)
            except Exception: pass

        ok, sibling_tracks = fetch_apple_music_motion(artist, title, album, target_apple_path)
        if ok:
            mark_used(target_apple_path)
            prune_cache()
            if track_id and not os.path.exists(os.path.join(CACHE_DIR, f"{track_id}.mp4")):
                try:
                    os.symlink(target_apple_path, os.path.join(CACHE_DIR, f"{track_id}.mp4"))
                except Exception:
                    pass
            # Create symlinks for all other tracks in the same album for 0ms instant playback
            if artist and sibling_tracks:
                for sib_title in sibling_tracks:
                    sib_clean = clean_song_title(sib_title)
                    for st in (sib_title, sib_clean):
                        sib_key = sanitize(f"{artist} - {st}".strip(" -"))
                        if sib_key and sib_key != sanitized_name:
                            sib_path = os.path.join(CACHE_DIR, f"{sib_key}.mp4")
                            try:
                                if not os.path.exists(sib_path) and not os.path.islink(sib_path):
                                    os.symlink(target_apple_path, sib_path)
                            except Exception:
                                pass
            if art_hash:
                art_map = load_art_mapping()
                art_map[art_hash] = {"videoPath": target_apple_path, "source": "applemusic", "isOfficial": True}
                save_art_mapping(art_map)
            print(json.dumps({"type": "video", "success": True, "videoPath": target_apple_path, "isOfficial": True, "source": "applemusic", "localArt": local_art}), flush=True)
            return

    # If Apple Music only mode, don't fallback to Spotify
    if not allow_spotify:
        print(json.dumps({"type": "video", "success": False, "videoPath": "", "isOfficial": False, "source": "none", "localArt": local_art}), flush=True)
        return

    # 4. Spotify Canvas
    canvas_mp4_url = None
    if not track_id:
        track_id = get_spotify_track_id(title)

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
            if art_hash:
                art_map = load_art_mapping()
                art_map[art_hash] = {"videoPath": save_path, "source": "spotify", "isOfficial": True}
                save_art_mapping(art_map)
            print(json.dumps({"type": "video", "success": True, "videoPath": save_path, "isOfficial": True, "source": "spotify", "localArt": local_art}), flush=True)
            return

    # 5. Fall back cleanly to blurred album art background
    print(json.dumps({"type": "video", "success": False, "videoPath": "", "isOfficial": False, "source": "none", "localArt": local_art}), flush=True)

if __name__ == "__main__":
    main()
