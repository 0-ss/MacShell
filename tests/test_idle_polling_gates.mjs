// Runs the idle-polling gate helpers from MacBar.qml / MacDock.qml.   node tests/test_idle_polling_gates.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

function fn(file, name) {
    const qml = readFileSync(new URL(`../MacShell/${file}`, import.meta.url), "utf8");
    const at = qml.indexOf(`function ${name}(`);
    assert.notEqual(at, -1, `${name} missing in ${file}`);
    const open = qml.indexOf("{", at);
    let end = open + 1;
    for (let depth = 1; depth > 0; end++) depth += qml[end] === "{" ? 1 : qml[end] === "}" ? -1 : 0;
    return new Function(`return (${qml.slice(at, end)})`)();
}

const dock = fn("MacDock.qml", "shouldRefreshDockForEvent");
for (const n of ["windowtitle", "windowtitlev2", "activewindow", "screencast", "screencastv2"]) assert.equal(dock(n), false, n);
for (const n of ["workspace", "openwindow", "closewindow", "focusedmon", "fullscreen"]) assert.equal(dock(n), true, n);

const discord = fn("MacBar.qml", "shouldPollDiscord");
assert.equal(discord(false, false, false, false), false);   // idle: nothing runs
assert.equal(discord(false, true, false, false), true);     // call streams
assert.equal(discord(false, false, true, false), true);     // Discord window open
assert.equal(discord(true, false, false, false), true);     // Audio Hub popover open
assert.equal(discord(false, false, false, true), true);     // was running: one more poll to see it quit

const earbuds = fn("MacBar.qml", "shouldPollEarbuds");
assert.equal(earbuds(false, false, 0, false), false);       // idle
assert.equal(earbuds(false, true, 0, false), false);        // BT on, nothing connected
assert.equal(earbuds(false, false, 2, false), false);       // stale count with BT off
assert.equal(earbuds(false, true, 1, false), true);         // a device is connected
assert.equal(earbuds(true, false, 0, false), true);         // popover open
assert.equal(earbuds(false, false, 0, true), true);         // was connected: one more poll to see it drop
console.log("ok");
