// Display-mode restore and the MacLock settings.json merge from MacDock.qml.   node tests/test_dock_settings.mjs
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync, existsSync, readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

// MacDock.qml plus the Settings window extracted from it (slotCmd lives there now)
const qml = ["MacDock.qml", "SettingsWindow.qml"].map(f => readFileSync(new URL(`../MacShell/${f}`, import.meta.url), "utf8")).join("\n");

// normalizeModeEntry
const fs = qml.indexOf("function normalizeModeEntry(");
const bs = qml.indexOf("{", qml.indexOf(")", fs)) + 1;
let be = bs;
for (let depth = 1; depth > 0; be++) depth += qml[be] === "{" ? 1 : qml[be] === "}" ? -1 : 0;
const normalize = new Function("entry", "liveMon", qml.slice(bs, be - 1));

const live = { name: "DP-1", x: 1920, y: 0, scale: 1.5 };
assert.deepEqual(normalize("2560x1440@144.00", live), { mode: "2560x1440@144.00", position: "1920x0", scale: 1.5 });
assert.deepEqual(normalize({ mode: "3840x2160@60.00", position: "0x0", scale: 2 }, live), { mode: "3840x2160@60.00", position: "0x0", scale: 2 });
assert.deepEqual(normalize("1920x1080@60.00", null), { mode: "1920x1080@60.00", position: "auto", scale: 1 });
assert.equal(normalize("", live), null);
assert.equal(normalize('1920x1080"; evil', live), null);
assert.equal(normalize({ mode: "1920x1080@60.00", position: '0x0" })', scale: -1 }, null).position, "auto");

// maclock/settings.json merge: run the real shell command in a temp HOME
const line = qml.split("\n").find(l => l.includes("readonly property string slotCmd:"));
const cmd = new Function("return " + line.slice(line.indexOf('"', line.indexOf("slotCmd:"))))();

function run(initial, slot) {
    const home = mkdtempSync(join(tmpdir(), "dock-settings-"));
    const file = join(home, ".config/maclock/settings.json");
    if (initial !== null) {
        execFileSync("mkdir", ["-p", join(home, ".config/maclock")]);
        writeFileSync(file, initial);
    }
    execFileSync("sh", ["-c", cmd, "sh", slot], { env: { ...process.env, HOME: home } });
    const leftovers = readdirSync(join(home, ".config/maclock")).filter(f => f !== "settings.json");
    assert.deepEqual(leftovers, [], "temp file left behind");
    return JSON.parse(readFileSync(file, "utf8"));
}

assert.deepEqual(run('{"canvasMode":"spotify","mediaSlot":"top"}', "bottom"), { canvasMode: "spotify", mediaSlot: "bottom" });
assert.deepEqual(run(null, "bottom"), { mediaSlot: "bottom" });
assert.deepEqual(run("{not json", "top"), { mediaSlot: "top" });
assert.deepEqual(run("", "top"), { mediaSlot: "top" });

console.log("ok");
