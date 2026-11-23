.pragma library

var FALLBACK_RATES_USD = {
    USD: 1.0, EUR: 0.92, GBP: 0.79, JPY: 154.0, CHF: 0.88, CAD: 1.39,
    AUD: 1.53, CNY: 7.24, SEK: 10.6, NOK: 10.9, DKK: 6.86, PLN: 4.02,
    BRL: 5.75, INR: 84.2, KRW: 1390.0, MXN: 20.1, TRY: 34.4
};

var CURRENCY_SYMBOLS = {
    "$": "USD", "usd": "USD", "dollar": "USD", "dollars": "USD",
    "\u20ac": "EUR", "eur": "EUR", "euro": "EUR", "euros": "EUR",
    "\u00a3": "GBP", "gbp": "GBP", "pound": "GBP", "pounds": "GBP",
    "\u00a5": "JPY", "jpy": "JPY", "yen": "JPY",
    "chf": "CHF", "cad": "CAD", "aud": "AUD", "cny": "CNY", "rmb": "CNY",
    "sek": "SEK", "nok": "NOK", "dkk": "DKK", "pln": "PLN", "brl": "BRL",
    "inr": "INR", "krw": "KRW", "mxn": "MXN", "try": "TRY"
};

function normCurrency(tok) {
    var k = String(tok || "").trim().toLowerCase();
    return CURRENCY_SYMBOLS[k] || "";
}

function parseCurrencyQuery(q, liveRates) {
    var s = String(q || "").trim();
    if (!s) return null;
    // Supports: "100 USD to EUR", "50€ in $", "$120 to eur", "42.5 gbp in chf"
    var m = /^([$€£¥])?\s*(\d+(?:[.,]\d+)?)\s*([$€£¥]|[a-zA-Z]{3,7})?\s+(?:to|in|=)\s+([$€£¥]|[a-zA-Z]{3,7})$/i.exec(s);
    if (!m) return null;
    var amount = parseFloat(m[2].replace(",", "."));
    if (isNaN(amount) || !isFinite(amount)) return null;
    var fromCode = normCurrency(m[1] || m[3]);
    var toCode = normCurrency(m[4]);
    if (!fromCode || !toCode || fromCode === toCode) return null;
    var rates = (liveRates && typeof liveRates === "object" && liveRates.EUR) ? liveRates : FALLBACK_RATES_USD;
    var rFrom = Number(rates[fromCode] || FALLBACK_RATES_USD[fromCode] || 0);
    var rTo = Number(rates[toCode] || FALLBACK_RATES_USD[toCode] || 0);
    if (rFrom <= 0 || rTo <= 0) return null;
    var converted = (amount / rFrom) * rTo;
    var decimals = (toCode === "JPY" || toCode === "KRW") ? 0 : 2;
    return {
        amount: amount,
        from: fromCode,
        to: toCode,
        result: converted,
        formatted: converted.toFixed(decimals) + " " + toCode,
        rateText: "1 " + fromCode + " = " + (rTo / rFrom).toFixed(4) + " " + toCode,
        live: !!(liveRates && liveRates.EUR)
    };
}

function parseDurationMs(str) {
    var s = String(str || "").trim().toLowerCase();
    if (!s) return 0;
    var total = 0, matched = false;
    var re = /(\d+)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)\b/g;
    var m;
    while ((m = re.exec(s)) !== null) {
        var n = parseInt(m[1], 10);
        var u = m[2].charAt(0);
        if (u === "h") total += n * 3600000;
        else if (u === "m") total += n * 60000;
        else if (u === "s") total += n * 1000;
        matched = true;
    }
    if (!matched && /^\d+$/.test(s)) {
        total = parseInt(s, 10) * 60000; // bare number defaults to minutes
        matched = total > 0;
    }
    return matched ? total : 0;
}

function parseQuickAction(q) {
    var s = String(q || "").trim();
    if (!s) return null;
    var tm = /^(?:timer|t)\s+(.+)$/i.exec(s);
    if (tm) {
        var rest = tm[1].trim();
        var durRe = /^((?:\d+\s*(?:h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)\b\s*)+|\d+)\s*(.*)$/i.exec(rest);
        if (durRe) {
            var ms = parseDurationMs(durRe[1]);
            if (ms > 0) return { kind: "timer", ms: ms, label: durRe[2].trim() };
        }
    }
    var nm = /^(?:note|n)\s+(.+)$/i.exec(s);
    if (nm && nm[1].trim()) return { kind: "note", text: nm[1].trim() };

    var rm = /^(?:remind|reminder|r)\s+(.+)$/i.exec(s);
    if (rm && rm[1].trim()) return { kind: "remind", text: rm[1].trim() };

    var fm = /^focus(?:\s+(.*))?$/i.exec(s);
    if (fm) return { kind: "focus", target: String(fm[1] || "").trim().toLowerCase() };

    var dm = /^(?:define|def|dict)\s+([a-zA-Z\-]{2,40})$/i.exec(s);
    if (dm) return { kind: "define", word: dm[1].trim().toLowerCase() };

    if (/^(?:weather|wetter)(?:\s+.*)?$/i.test(s)) return { kind: "weather" };

    var sm = /^(?:stock\s+|\$)([a-zA-Z.\-]{1,10})$/i.exec(s);
    if (sm) return { kind: "stock", symbol: sm[1].toUpperCase() };

    return null;
}

function fileKindFromPath(path, isDir) {
    if (isDir) return "dir";
    var s = String(path || "").toLowerCase();
    var dot = s.lastIndexOf(".");
    var ext = dot >= 0 ? s.substring(dot + 1) : "";
    if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif"].indexOf(ext) >= 0) return "image";
    if (ext === "pdf") return "pdf";
    if (["mp4", "mkv", "webm", "mov", "avi"].indexOf(ext) >= 0) return "video";
    if (["mp3", "flac", "wav", "ogg", "m4a", "opus"].indexOf(ext) >= 0) return "audio";
    if (["txt", "md", "json", "js", "ts", "py", "qml", "sh", "lua", "toml", "yaml", "yml", "ini", "conf", "css", "html", "xml", "c", "cpp", "h", "rs", "go", "log", "csv"].indexOf(ext) >= 0) return "text";
    return "file";
}

function formatBytes(bytes) {
    var b = Number(bytes) || 0;
    if (b <= 0) return "";
    if (b < 1024) return b + " B";
    if (b < 1048576) return (b / 1024).toFixed(1) + " KB";
    if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB";
    return (b / 1073741824).toFixed(2) + " GB";
}

function parseSearchJson(text) {
    try {
        var arr = JSON.parse(String(text || "[]"));
        if (!Array.isArray(arr)) return [];
        return arr.filter(function (x) { return x && typeof x.path === "string" && x.path !== ""; });
    } catch (e) {
        return [];
    }
}

function parseDictionaryJson(text, word) {
    try {
        var data = JSON.parse(String(text || "[]"));
        if (!Array.isArray(data) || data.length === 0) return null;
        var entry = data[0];
        var meanings = Array.isArray(entry.meanings) ? entry.meanings : [];
        var defs = [];
        for (var i = 0; i < meanings.length && defs.length < 3; i++) {
            var pos = meanings[i].partOfSpeech || "";
            var list = Array.isArray(meanings[i].definitions) ? meanings[i].definitions : [];
            if (list.length > 0 && list[0].definition) {
                defs.push({ pos: pos, text: String(list[0].definition) });
            }
        }
        if (defs.length === 0) return null;
        return {
            word: String(entry.word || word || ""),
            phonetic: String(entry.phonetic || ""),
            defs: defs
        };
    } catch (e) {
        return null;
    }
}
