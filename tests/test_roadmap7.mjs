// Unit tests for Roadmap #7 (Continuity/AirDrop, Time Machine UI, Aerial Screensavers, Finder Companion).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

function loadPragmaLib(relPath, exportsList) {
    const src = readFileSync(new URL(`../${relPath}`, import.meta.url), "utf8")
        .replace(/^\s*\.pragma\s+library\s*/m, "");
    return new Function(`${src}\nreturn { ${exportsList.join(", ")} };`)();
}

const ECO = loadPragmaLib("MacShell/Ecosystem.js", [
    "FINDER_TAGS", "parseKdeConnectDevices", "parseSnapperList",
    "parseTimeshiftList", "toggleFileTag", "taggedPaths", "parentDir"
]);

// KDE Connect device parsing
const devs = ECO.parseKdeConnectDevices("- Pixel 9: dev_123 (paired and reachable)\n- iPad: dev_456 (paired)\n");
assert.equal(devs.length, 2);
assert.equal(devs[0].name, "Pixel 9");
assert.equal(devs[0].reachable, true);
assert.equal(devs[1].reachable, false);

// Snapper CSV + pipe parsing
const snaps = ECO.parseSnapperList(
    "config,subvolume,number,default,active,type,pre-number,date,user,used-space,cleanup,description,userdata\n" +
    "root,/,0,yes,yes,single,,2026-11-01,root,,number,current,\n" +
    "root,/,42,no,no,pre,,2026-11-23 12:00,root,12 MiB,number,pacman upgrade,\n"
);
assert.equal(snaps.length, 1);
assert.equal(snaps[0].id, "42");
assert.equal(snaps[0].path, "/.snapshots/42/snapshot");

const ts = ECO.parseTimeshiftList("2026-11-23_12-00-00\n");
assert.equal(ts.length, 1);
assert.equal(ts[0].backend, "timeshift");

// Finder tags & parentDir
let tags = ECO.toggleFileTag({}, "/home/u/doc.pdf", "blue");
tags = ECO.toggleFileTag(tags, "/home/u/doc.pdf", "red");
assert.deepEqual(ECO.taggedPaths(tags, "blue"), ["/home/u/doc.pdf"]);
tags = ECO.toggleFileTag(tags, "/home/u/doc.pdf", "blue");
assert.deepEqual(ECO.taggedPaths(tags, "blue"), []);
assert.equal(ECO.parentDir("/home/u/Documents"), "/home/u");
assert.equal(ECO.parentDir("/"), "/");

// Wiring checks
const shell = readFileSync(new URL("../MacShell/shell.qml", import.meta.url), "utf8");
for (const t of ["continuity", "timemachine", "finder"]) {
    assert.ok(shell.includes(`target: "${t}"`), `shell.qml missing IPC target ${t}`);
}
const lockShell = readFileSync(new URL("../MacLock/shell.qml", import.meta.url), "utf8");
const lockScreen = readFileSync(new URL("../MacLock/LockScreen.qml", import.meta.url), "utf8");
assert.ok(lockShell.includes("aerialVideo") && lockScreen.includes("aerialFreezeT"), "MacLock Aerial Screensavers missing");

const roadmap = readFileSync(new URL("../ROADMAP.md", import.meta.url), "utf8");
assert.ok(!roadmap.includes("- [ ]"), "All roadmap items should be completed");

console.log("ok");
