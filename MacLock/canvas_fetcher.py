#!/usr/bin/env python3
"""Resolve Apple Music Motion or Spotify Canvas for the current track."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlencode, urljoin, urlsplit
from urllib.request import Request, urlopen

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "maclock"
ART_CACHE = CACHE / "art"
MOTION_CACHE = CACHE / "motion"
MAX_MOTION_BYTES = 20 * 1024 * 1024
USER_AGENT = "Mozilla/5.0"


def read_url(url, limit, timeout=5):
    if urlsplit(url).scheme not in {"http", "https"}:
        raise ValueError("Expected an HTTP URL")
    with urlopen(Request(url, headers={"User-Agent": USER_AGENT}), timeout=timeout) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Response exceeded the size limit")
    return data


def cache_key(value):
    return hashlib.sha256(value.encode()).hexdigest()


def prune(folder, count, limit):
    files = sorted(
        (p for p in folder.iterdir() if p.is_file() and not p.name.startswith(".")),
        key=lambda p: p.stat().st_mtime_ns, reverse=True,
    )
    total = 0
    for i, file in enumerate(files):
        total += file.stat().st_size
        if i >= count or total > limit:
            file.unlink(missing_ok=True)


def local_art(url):
    if not url or urlsplit(url).scheme not in {"http", "https"}:
        return ""
    ART_CACHE.mkdir(parents=True, exist_ok=True)
    path = ART_CACHE / cache_key(url)
    if not path.is_file():
        data = read_url(url, 8 * 1024 * 1024, timeout=3.5)
        with tempfile.NamedTemporaryFile(dir=ART_CACHE, prefix=".", delete=False) as output:
            tmp = Path(output.name)
            output.write(data)
        try:
            tmp.replace(path)
        finally:
            tmp.unlink(missing_ok=True)
    path.touch()
    prune(ART_CACHE, 16, 16 * 1024 * 1024)
    return str(path) if path.is_file() else ""


def apple_album_url(title, artist, album):
    normalize = lambda text: " ".join(re.findall(r"\w+", text.casefold()))
    wanted_title = normalize(title)
    wanted_artist = normalize(artist)
    wanted_album = normalize(album)
    if not wanted_title or not wanted_artist:
        return ""
    query = urlencode({"term": f"{artist} {title}", "entity": "song", "limit": 10})
    results = json.loads(read_url(f"https://itunes.apple.com/search?{query}", 1024 * 1024))
    for item in results.get("results", []):
        if normalize(item.get("trackName", "")) != wanted_title:
            continue
        if normalize(item.get("artistName", "")) != wanted_artist:
            continue
        if wanted_album and normalize(item.get("collectionName", "")) != wanted_album:
            continue
        url = urlsplit(item.get("collectionViewUrl", ""))
        if url.scheme == "https" and url.netloc == "music.apple.com" and "/album/" in url.path:
            return f"https://music.apple.com{url.path}"
    return ""


def apple_playlist(album_url):
    # The public album page embeds the same previews displayed by the web player.
    page = read_url(album_url, 4 * 1024 * 1024).decode("utf-8")
    match = re.search(r'<script[^>]+id="serialized-server-data"[^>]*>(.*?)</script>', page, re.S)
    if not match:
        return ""
    page_data = json.loads(match[1])
    for response in page_data.get("data", []):
        for section in response.get("data", {}).get("sections", []):
            for item in section.get("items", []):
                for field, detail in (("tallVideoArtwork", "motionDetailTall"), ("videoArtwork", "motionDetailSquare")):
                    video = (item.get(field) or {}).get("dictionary", {}).get(detail, {}).get("video", "")
                    url = urlsplit(video)
                    if url.scheme == "https" and url.netloc == "mvod.itunes.apple.com" and url.path.endswith(".m3u8"):
                        return video
    return ""


def select_variant(playlist_url):
    playlist = read_url(playlist_url, 256 * 1024).decode("utf-8")
    variants = []
    for match in re.finditer(r"^#EXT-X-STREAM-INF:(.*)\r?\n([^#\r\n]+)", playlist, re.M):
        bandwidth = re.search(r"(?:^|,)BANDWIDTH=(\d+)", match[1])
        url = urljoin(playlist_url, match[2].strip())
        if bandwidth and urlsplit(url).netloc == "mvod.itunes.apple.com":
            variants.append((int(bandwidth[1]), url))
    if not variants:
        return playlist_url
    return max((v for v in variants if v[0] <= 4_500_000), default=min(variants))[1]


def apple_motion(title, artist, album, art_url):
    MOTION_CACHE.mkdir(parents=True, exist_ok=True)
    album_key = f"{artist}\0{album or title}\0{art_url}"
    target = MOTION_CACHE / f"{cache_key(album_key)}.mp4"
    if target.is_file():
        target.touch()
        return str(target)
    album_url = apple_album_url(title, artist, album)
    playlist_url = apple_playlist(album_url) if album_url else ""
    if not playlist_url:
        return ""
    variant = select_variant(playlist_url)
    with tempfile.TemporaryDirectory(dir=MOTION_CACHE, prefix=".download-") as work:
        output = Path(work) / "motion.mp4"
        result = subprocess.run(
            ["ffmpeg", "-nostdin", "-v", "error", "-protocol_whitelist", "https,tls,tcp,crypto",
             "-i", variant, "-map", "0:v:0", "-c", "copy", "-t", "30", "-fs", str(MAX_MOTION_BYTES),
             "-movflags", "+faststart", str(output)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20, check=False,
        )
        if result.returncode or not output.is_file() or output.stat().st_size <= 1000:
            return ""
        output.replace(target)
    prune(MOTION_CACHE, 4, MAX_MOTION_BYTES)
    return str(target) if target.is_file() else ""


def spotify_canvas(track_id, title):
    from_path = Path(__file__).with_name("spotify-canvas.py")
    result = subprocess.run(
        [sys.executable, str(from_path), track_id or title], capture_output=True, text=True, timeout=34, check=False,
    )
    path = result.stdout.strip()
    return path if result.returncode == 0 and path and Path(path).is_file() else ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("both", "applemusic", "spotify"), default="both")
    parser.add_argument("title")
    parser.add_argument("artist")
    parser.add_argument("album")
    parser.add_argument("art_url")
    parser.add_argument("track_id")
    parser.add_argument("is_spotify", choices=("yes", "no"))
    args = parser.parse_args()

    try:
        art = local_art(args.art_url)
    except (OSError, ValueError):
        art = ""
    if art:
        print(json.dumps({"localArt": art}), flush=True)

    video = ""
    source = ""
    if args.mode != "spotify":
        try:
            video = apple_motion(args.title, args.artist, args.album, args.art_url)
            if video:
                source = "applemusic"
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
    if not video and args.mode != "applemusic" and (args.track_id or args.is_spotify == "yes"):
        try:
            video = spotify_canvas(args.track_id, args.title)
            if video:
                source = "spotify"
        except (OSError, subprocess.SubprocessError):
            pass
    print(json.dumps({"videoPath": video, "source": source}), flush=True)


if __name__ == "__main__":
    main()
