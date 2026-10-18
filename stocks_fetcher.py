#!/usr/bin/env python3
import sys
import os
import json
import time
import urllib.request

CACHE_FILE = "/tmp/macwidgets_stocks.json"
CACHE_TTL = 90  # 90 seconds cache

FALLBACK_DATA = [
    {
        "symbol": "BTC",
        "name": "Bitcoin",
        "price": 82050.0,
        "change24h": 1.45,
        "currency": "$",
        "sparkline": [80500, 80800, 81200, 80900, 81500, 81800, 82050]
    },
    {
        "symbol": "ETH",
        "name": "Ethereum",
        "price": 2420.5,
        "change24h": -0.75,
        "currency": "$",
        "sparkline": [2450, 2440, 2435, 2410, 2415, 2425, 2420.5]
    },
    {
        "symbol": "SOL",
        "name": "Solana",
        "price": 104.2,
        "change24h": 2.10,
        "currency": "$",
        "sparkline": [101, 102.5, 101.8, 103.2, 102.9, 104.5, 104.2]
    },
    {
        "symbol": "AAPL",
        "name": "Apple",
        "price": 235.8,
        "change24h": 0.85,
        "currency": "$",
        "sparkline": [233, 234.2, 233.8, 235.1, 234.9, 235.5, 235.8]
    },
    {
        "symbol": "NVDA",
        "name": "NVIDIA",
        "price": 138.6,
        "change24h": 3.42,
        "currency": "$",
        "sparkline": [133.5, 134.8, 136.2, 135.4, 137.0, 138.2, 138.6]
    }
]

def fetch_crypto():
    results = []
    try:
        url = "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=bitcoin,ethereum,solana&sparkline=true"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            for c in data:
                raw_spark = c.get("sparkline_in_7d", {}).get("price", [])
                # Downsample 168 pts to ~14 pts
                step = max(1, len(raw_spark) // 14)
                sampled_spark = raw_spark[::step][-14:] if raw_spark else []
                results.append({
                    "symbol": c.get("symbol", "").upper(),
                    "name": c.get("name", ""),
                    "price": round(float(c.get("current_price", 0)), 2),
                    "change24h": round(float(c.get("price_change_percentage_24h", 0)), 2),
                    "currency": "$",
                    "sparkline": sampled_spark
                })
    except Exception as e:
        pass
    return results

def fetch_stock_yahoo(symbol, name):
    try:
        url = f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1d&interval=15m"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            res = data.get("chart", {}).get("result", [{}])[0]
            meta = res.get("meta", {})
            curr_price = meta.get("regularMarketPrice") or meta.get("chartPreviousClose") or 0
            prev_close = meta.get("chartPreviousClose") or curr_price or 1
            change_pct = round(((curr_price - prev_close) / prev_close) * 100, 2)
            quote = res.get("indicators", {}).get("quote", [{}])[0].get("close", [])
            valid_pts = [round(float(p), 2) for p in quote if p is not None]
            # Downsample to ~14 pts
            step = max(1, len(valid_pts) // 14)
            sampled = valid_pts[::step][-14:] if valid_pts else []
            return {
                "symbol": symbol,
                "name": name,
                "price": round(float(curr_price), 2),
                "change24h": change_pct,
                "currency": "$",
                "sparkline": sampled
            }
    except Exception:
        pass
    return None

def main():
    now = time.time()
    # Check cache
    if os.path.exists(CACHE_FILE):
        try:
            mtime = os.path.getmtime(CACHE_FILE)
            if now - mtime < CACHE_TTL:
                with open(CACHE_FILE, "r", encoding="utf-8") as f:
                    print(f.read())
                    return
        except Exception:
            pass

    items = []
    # 1. Fetch Crypto
    crypto_list = fetch_crypto()
    if crypto_list:
        items.extend(crypto_list)
    else:
        # Fallback crypto
        items.extend([FALLBACK_DATA[0], FALLBACK_DATA[1], FALLBACK_DATA[2]])

    # 2. Fetch AAPL & NVDA
    for sym, nm in [("AAPL", "Apple"), ("NVDA", "NVIDIA")]:
        st = fetch_stock_yahoo(sym, nm)
        if st:
            items.append(st)
        else:
            fb = next((x for x in FALLBACK_DATA if x["symbol"] == sym), None)
            if fb:
                items.append(fb)

    out_json = json.dumps(items, ensure_ascii=False)
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            f.write(out_json)
    except Exception:
        pass

    print(out_json)

if __name__ == "__main__":
    main()

