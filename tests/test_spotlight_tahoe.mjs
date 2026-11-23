// Unit tests for Roadmap #4 (Spotlight Tahoe: Full-Text Search, Quick Look Pane, Quick Keys, Knowledge Cards).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

function loadPragmaLib(relPath, exportsList) {
    const src = readFileSync(new URL(`../${relPath}`, import.meta.url), "utf8")
        .replace(/^\s*\.pragma\s+library\s*/m, "");
    return new Function(`${src}\nreturn { ${exportsList.join(", ")} };`)();
}

const SP = loadPragmaLib("MacShell/Spotlight.js", [
    "FALLBACK_RATES_USD", "parseCurrencyQuery", "parseDurationMs", "parseQuickAction",
    "fileKindFromPath", "formatBytes", "parseSearchJson", "parseDictionaryJson"
]);

// Currency conversion
const fx1 = SP.parseCurrencyQuery("100 USD to EUR", { USD: 1.0, EUR: 0.90 });
assert.equal(fx1.from, "USD");
assert.equal(fx1.to, "EUR");
assert.equal(fx1.formatted, "90.00 EUR");
assert.equal(fx1.live, true);

const fx2 = SP.parseCurrencyQuery("50€ in $", null);
assert.equal(fx2.from, "EUR");
assert.equal(fx2.to, "USD");
assert.equal(fx2.live, false);
assert.ok(fx2.result > 50);

assert.equal(SP.parseCurrencyQuery("100 USD to USD", null), null);
assert.equal(SP.parseCurrencyQuery("hello world", null), null);

// Quick Keys & Duration parsing
assert.equal(SP.parseDurationMs("5m"), 300000);
assert.equal(SP.parseDurationMs("1h 30m 10s"), 5410000);
assert.equal(SP.parseDurationMs("10"), 600000);

assert.deepEqual(SP.parseQuickAction("t 5m Tea"), { kind: "timer", ms: 300000, label: "Tea" });
assert.deepEqual(SP.parseQuickAction("note Buy oat milk"), { kind: "note", text: "Buy oat milk" });
assert.deepEqual(SP.parseQuickAction("remind Standup at 10"), { kind: "remind", text: "Standup at 10" });
assert.deepEqual(SP.parseQuickAction("focus work"), { kind: "focus", target: "work" });
assert.deepEqual(SP.parseQuickAction("define serendipity"), { kind: "define", word: "serendipity" });
assert.deepEqual(SP.parseQuickAction("weather"), { kind: "weather" });
assert.deepEqual(SP.parseQuickAction("$aapl"), { kind: "stock", symbol: "AAPL" });
assert.deepEqual(SP.parseQuickAction("stock msft"), { kind: "stock", symbol: "MSFT" });

// File kind & size helpers
assert.equal(SP.fileKindFromPath("/tmp/a.png", false), "image");
assert.equal(SP.fileKindFromPath("/tmp/doc.pdf", false), "pdf");
assert.equal(SP.fileKindFromPath("/tmp/main.py", false), "text");
assert.equal(SP.fileKindFromPath("/tmp/dir", true), "dir");
assert.equal(SP.formatBytes(1536), "1.5 KB");

// Dictionary JSON parsing
const dict = SP.parseDictionaryJson(JSON.stringify([{
    word: "test",
    phonetic: "/tɛst/",
    meanings: [{ partOfSpeech: "noun", definitions: [{ definition: "A procedure to establish quality." }] }]
}]), "test");
assert.equal(dict.word, "test");
assert.equal(dict.defs[0].pos, "noun");

// Wiring checks in MacBar.qml
const bar = readFileSync(new URL("../MacShell/MacBar.qml", import.meta.url), "utf8");
assert.ok(bar.includes("spotlight-search.py"), "Full-text spotlight-search.py missing");
assert.ok(bar.includes("spPreviewPane"), "Quick Look split preview pane missing");
assert.ok(bar.includes("spotlightActions"), "Custom Spotlight actions setting missing");
assert.ok(bar.includes("Spotlight.parseCurrencyQuery") && bar.includes("Spotlight.parseQuickAction"), "Spotlight Knowledge Cards / Quick Keys missing");

console.log("ok");
