// Unit tests for Roadmap #6 (CaptureSuite, PolkitAuth, SystemDialogs, and all 8 System Settings panes).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

function loadPragmaLib(relPath, exportsList) {
    const src = readFileSync(new URL(`../${relPath}`, import.meta.url), "utf8")
        .replace(/^\s*\.pragma\s+library\s*/m, "");
    return new Function(`${src}\nreturn { ${exportsList.join(", ")} };`)();
}

const SP = loadPragmaLib("MacShell/SystemSettingsPanes.js", [
    "parseStorageBreakdown", "parseAutostartList", "parsePrinters", "parseTimedatectl", "parseUpdatesCount"
]);

const st = SP.parseStorageBreakdown("DF\t104857600\t52428800\t52428800\nCAT\tDocuments\t1048576\nCAT\tCache\t2097152\n");
assert.equal(Math.round(st.totalGb), 100);
assert.equal(st.segments.length, 2);
assert.equal(st.segments[0].name, "Documents");

const auto = SP.parseAutostartList("/a/foo.desktop\tFoo\t0\n/a/bar.desktop\tBar\t1\n");
assert.equal(auto.length, 2);
assert.equal(auto[0].enabled, true);
assert.equal(auto[1].enabled, false);

const pr = SP.parsePrinters("printer HP_LaserJet is idle. enabled since Mon\n");
assert.equal(pr.length, 1);
assert.equal(pr[0].name, "HP_LaserJet");

const td = SP.parseTimedatectl("               Time zone: Europe/Berlin (CET, +0100)\n             NTP service: active\n");
assert.equal(td.timezone, "Europe/Berlin");
assert.equal(td.ntp, true);

const up = SP.parseUpdatesCount("linux 7.3.5-1 -> 7.3.5-2\nmesa 25.0 -> 25.1\n");
assert.equal(up.count, 2);

// Wiring assertions
const shell = readFileSync(new URL("../MacShell/shell.qml", import.meta.url), "utf8");
for (const t of ["capture", "forcequit", "activity", "polkit"]) {
    assert.ok(shell.includes(`target: "${t}"`), `shell.qml missing IPC target ${t}`);
}
const settings = readFileSync(new URL("../MacShell/SettingsWindow.qml", import.meta.url), "utf8");
for (const p of ["paneStorage", "panePrivacy", "paneAccessibility", "paneLoginItems", "paneDateTime", "panePrinters", "paneSharing", "paneSysUpdate"]) {
    assert.ok(settings.includes(`id: ${p}`), `SettingsWindow.qml missing ${p}`);
}

console.log("ok");
