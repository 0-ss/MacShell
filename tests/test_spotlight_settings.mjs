// Tests Spotlight's settingsItems() and homeItems() against the real settingsPanes catalog in MacDock.qml.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (rel) => readFileSync(new URL(rel, import.meta.url), "utf8");
const dockQml = read("../MacShell/MacDock.qml");
const barQml = read("../MacShell/MacBar.qml");

function extractBracketed(src, marker, open, close) {
    const start = src.indexOf(open, src.indexOf(marker));
    assert.ok(start >= 0, `Could not find ${marker}`);
    let depth = 0;
    for (let i = start; i < src.length; i++) {
        if (src[i] === open) depth++;
        else if (src[i] === close && --depth === 0) return src.slice(start, i + 1);
    }
    throw new Error(`Unclosed block for ${marker}`);
}

const panesLit = extractBracketed(dockQml, "readonly property var settingsPanes:", "[", "]");
const settingsPanes = new Function(`return (${panesLit});`)();
assert.ok(settingsPanes.length >= 20, "settingsPanes catalog must contain Settings panes");

const settingsBody = extractBracketed(barQml, "function settingsItems(q, limit)", "{", "}").slice(1, -1);
const actionBody = extractBracketed(barQml, "function actionItems(q)", "{", "}").slice(1, -1);
const homeBody = extractBracketed(barQml, "function homeItems(q)", "{", "}").slice(1, -1);

const settingsItemsFn = new Function("q", "limit", "hub", "root", "I18n", settingsBody);
const actionItemsFn = new Function("q", "root", "openSettings", "sh", "I18n", actionBody);
const homeItemsFn = new Function(
    "q", "isScreenshotQuery", "screenshotItems", "recentItems", "recentLoading",
    "fileQuery", "updateFileSearch", "fileItems", "fileSearchPending",
    "appItems", "conversion", "calcValue", "windowItems", "actionItems", "settingsItems",
    "Quickshell", "I18n",
    homeBody,
);

const I18n = { tr: (s) => s };
function query(q, opts = {}) {
    const opened = [];
    const hub = { dock: { settingsEnabled: opts.enabled !== false, settingsPanes } };
    const root = { openSettings: (id) => opened.push(id), lockScreen: () => {}, sleepMachine: () => {}, logOut: () => {} };
    const items = settingsItemsFn(q, opts.limit, hub, root, I18n);
    return { items, opened };
}

function queryHome(q, { apps = [], wins = [], enabled = true } = {}) {
    const opened = [];
    let locked = false;
    const hub = { dock: { settingsEnabled: enabled, settingsPanes } };
    const root = {
        openSettings: (id) => opened.push(id),
        lockScreen: () => { locked = true; },
        sleepMachine: () => {},
        logOut: () => {},
    };
    const items = homeItemsFn(
        q,
        () => false, () => [], () => [], false,
        "", () => {}, () => [], false,
        (_q, lim) => apps.slice(0, lim),
        () => null,
        () => null,
        () => wins,
        (aq) => actionItemsFn(aq, root, (id) => root.openSettings(id), () => {}, I18n),
        (sq, lim) => settingsItemsFn(sq, lim, hub, root, I18n),
        { execDetached: () => {} },
        I18n,
    );
    return { items, opened, get locked() { return locked; } };
}

// Keyword match: "night shift" -> Displays
{
    const { items, opened } = query("night shift");
    assert.equal(items.length, 1);
    assert.equal(items[0].title, "Displays");
    assert.equal(items[0].sub, "System Settings");
    assert.equal(items[0].glyph, "gear");
    items[0].run();
    assert.deepEqual(opened, ["displays"]);
}

// Hyphen-insensitive match: "wifi" -> Wi-Fi first
{
    const { items, opened } = query("wifi");
    assert.ok(items.length >= 1);
    assert.equal(items[0].title, "Wi-Fi");
    items[0].run();
    assert.deepEqual(opened, ["wifi"]);
}

// Exact name beats keyword match: "wallpaper" -> Wallpaper
{
    const { items, opened } = query("wallpaper");
    assert.equal(items[0].title, "Wallpaper");
    items[0].run();
    assert.deepEqual(opened, ["wallpaper"]);
}

// Tailscale keyword -> Network
{
    const { items, opened } = query("tailscale");
    assert.equal(items[0].title, "Network");
    items[0].run();
    assert.deepEqual(opened, ["network"]);
}

// homeItems(): "Lock Screen" keeps the session lock action first, with Lock Screen settings second
{
    const res = queryHome("Lock Screen");
    assert.equal(res.items[0].title, "Lock Screen");
    assert.equal(res.items[0].sub, "Action");
    res.items[0].run();
    assert.equal(res.locked, true);
    assert.equal(res.items[1].title, "Lock Screen");
    assert.equal(res.items[1].sub, "System Settings");
    res.items[1].run();
    assert.deepEqual(res.opened, ["lockscreen"]);
}

// homeItems(): 5 app+window hits for "lock" keep both the Lock Screen action and the Settings pane
{
    const apps = [1, 2, 3, 4].map((n) => ({ title: `Lock App ${n}`, sub: "Application" }));
    const wins = [{ title: "Lock Window 1", sub: "Open Window" }];
    const res = queryHome("lock", { apps, wins });
    const actIdx = res.items.findIndex((it) => it.title === "Lock Screen" && it.sub === "Action");
    const prefIdx = res.items.findIndex((it) => it.title === "Lock Screen" && it.sub === "System Settings");
    assert.ok(actIdx >= 0, "Lock Screen action must not be evicted by Settings slot reservation");
    assert.ok(prefIdx > actIdx, "Lock Screen Settings pane must appear after Lock Screen action");
}

// homeItems(): 6 app+window hits still reserve a slot for the top Settings match
{
    const apps = [1, 2, 3, 4].map((n) => ({ title: `App ${n}`, sub: "Application" }));
    const wins = [1, 2].map((n) => ({ title: `Win ${n}`, sub: "Open Window" }));
    const res = queryHome("sound", { apps, wins });
    const pref = res.items.find((it) => it.sub === "System Settings");
    assert.ok(pref, "top Settings match must still appear when 6 apps/windows match");
    assert.equal(pref.title, "Sound");
    pref.run();
    assert.deepEqual(res.opened, ["sound"]);
}

// homeItems(): when Settings is disabled, 6 app+window hits for "lock" keep all 6 unchanged
{
    const apps = [1, 2, 3, 4].map((n) => ({ title: `Lock App ${n}`, sub: "Application" }));
    const wins = [1, 2].map((n) => ({ title: `Lock Window ${n}`, sub: "Open Window" }));
    const res = queryHome("lock", { apps, wins, enabled: false });
    assert.deepEqual(
        res.items.slice(0, 6).map((it) => it.title),
        ["Lock App 1", "Lock App 2", "Lock App 3", "Lock App 4", "Lock Window 1", "Lock Window 2"],
    );
}

// Short, punctuation-only, and disabled settings queries return nothing
assert.deepEqual(query("").items, []);
assert.deepEqual(query("w").items, []);
assert.deepEqual(query("---").items, []);
assert.deepEqual(query("bluetooth", { enabled: false }).items, []);

console.log("ok");
