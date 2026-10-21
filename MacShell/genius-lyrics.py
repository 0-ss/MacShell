#!/usr/bin/env python3
"""
Genius Lyrics Fetcher for MacShell and MacLock
Fetches lyrics from Genius token-free, caches results in JSON.
Output format: {"plain": str, "lines": [{"t": -1, "text": str}], "source": "genius"}
"""

import sys
import os
import re
import json
import urllib.parse
import urllib.request
from html.parser import HTMLParser

class GeniusLyricsParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_lyrics_container = 0
        self.lyrics_parts = []
        self.ignore_tags = {"script", "style", "header", "nav", "footer"}
        self.current_ignore = 0

    def handle_starttag(self, tag, attrs):
        attr_dict = dict(attrs)
        if tag in self.ignore_tags:
            self.current_ignore += 1
            return
        if attr_dict.get("data-lyrics-container") == "true" or "Lyrics__Container" in attr_dict.get("class", ""):
            self.in_lyrics_container += 1
        elif self.in_lyrics_container > 0 and tag in ("br", "p", "div"):
            self.lyrics_parts.append("\n")

    def handle_endtag(self, tag):
        if tag in self.ignore_tags:
            self.current_ignore = max(0, self.current_ignore - 1)
            return
        if self.in_lyrics_container > 0:
            if tag in ("p", "div"):
                self.lyrics_parts.append("\n")

    def handle_data(self, data):
        if self.current_ignore > 0:
            return
        if self.in_lyrics_container > 0:
            self.lyrics_parts.append(data)

    def get_lyrics(self):
        text = "".join(self.lyrics_parts)
        # Normalize whitespace and excessive newlines
        lines = [line.strip() for line in text.split("\n")]
        # Remove consecutive blank lines
        cleaned = []
        for line in lines:
            if line:
                cleaned.append(line)
            elif cleaned and cleaned[-1] != "":
                cleaned.append("")
        return "\n".join(cleaned).strip()

def clean_title(title):
    # Remove (feat. X), [Remastered], etc.
    t = re.sub(r'[\(\[][^\)\]]*[\)\]]', '', title)
    t = re.sub(r' - .*$', '', t)
    return t.strip()

def fetch_genius_lyrics(artist, title, cache_dir):
    os.makedirs(cache_dir, exist_ok=True)
    cache_key = re.sub(r'[^a-zA-Z0-9]', '_', f"{artist}_{title}".lower())[:32]
    cache_file = os.path.join(cache_dir, f"genius_{cache_key}.json")

    if os.path.exists(cache_file) and os.path.getsize(cache_file) > 10:
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass

    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    }

    query = f"{artist} {clean_title(title)}".strip()
    search_url = "https://genius.com/api/search/multi?q=" + urllib.parse.quote(query)

    try:
        req = urllib.request.Request(search_url, headers=headers)
        with urllib.request.urlopen(req, timeout=7) as resp:
            data = json.loads(resp.read().decode("utf-8", "ignore"))

        song_path = None
        sections = data.get("response", {}).get("sections", [])
        for sec in sections:
            if sec.get("type") == "song":
                hits = sec.get("hits", [])
                if hits:
                    song_path = hits[0].get("result", {}).get("path")
                    break

        if not song_path:
            return None

        song_url = f"https://genius.com{song_path}"
        req_page = urllib.request.Request(song_url, headers=headers)
        with urllib.request.urlopen(req_page, timeout=8) as page_resp:
            html = page_resp.read().decode("utf-8", "ignore")

        parser = GeniusLyricsParser()
        parser.feed(html)
        lyrics_text = parser.get_lyrics()

        if not lyrics_text or len(lyrics_text) < 20:
            # Fallback regex extraction if class structure slightly differed
            containers = re.findall(r'<div[^>]*data-lyrics-container="true"[^>]*>(.*?)</div>', html, re.DOTALL)
            if containers:
                raw = "\n".join(containers)
                raw = re.sub(r'<br\s*/?>', '\n', raw)
                raw = re.sub(r'<[^>]+>', '', raw)
                lyrics_text = raw.strip()

        if lyrics_text and len(lyrics_text) >= 20:
            lines_data = []
            for l in lyrics_text.split("\n"):
                s = l.strip()
                if s:
                    lines_data.append({"t": -1, "text": s})

            result = {
                "plain": lyrics_text,
                "lines": lines_data,
                "source": "genius"
            }
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump(result, f, ensure_ascii=False)
            return result
    except Exception as e:
        pass

    return None

def main():
    if len(sys.argv) < 3:
        print(json.dumps({}))
        return

    artist = sys.argv[1].strip()
    title = sys.argv[2].strip()
    cache_dir = sys.argv[3].strip() if len(sys.argv) > 3 else os.path.expanduser("~/.cache/macshell/lyrics")

    result = fetch_genius_lyrics(artist, title, cache_dir)
    if result:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(json.dumps({}))

if __name__ == "__main__":
    main()
