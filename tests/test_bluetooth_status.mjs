// Runs the btProc result handler from MacBar.qml on a canned BlueZ reply.   node tests/test_bluetooth_status.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const qml = readFileSync(new URL("../MacShell/MacBar.qml", import.meta.url), "utf8");
const start = qml.indexOf("{", qml.indexOf("onStreamFinished:", qml.indexOf("id: btProc"))) + 1;
let end = start;
for (let depth = 1; depth > 0; end++) depth += qml[end] === "{" ? 1 : qml[end] === "}" ? -1 : 0;
const handler = new Function("text", "root", qml.slice(start, end - 1));

function run(text) {
    const root = { btDevices: [], btIconFor: () => "bluetooth" };
    handler(text, root);
    return root;
}

const v = (type, data) => ({ type, data });
const reply = JSON.stringify({ type: "a{oa{sa{sv}}}", data: [{
    "/org/bluez": { "org.bluez.AgentManager1": {} },
    "/org/bluez/hci0": { "org.bluez.Adapter1": { Powered: v("b", true) } },
    "/org/bluez/hci0/dev_AA": { "org.bluez.Device1": { Address: v("s", "AA:AA"), Alias: v("s", "Speaker"),
        Paired: v("b", true), Bonded: v("b", true), Connected: v("b", false) } },
    "/org/bluez/hci0/dev_BB": { "org.bluez.Device1": { Address: v("s", "BB:BB"), Alias: v("s", "Buds"),
        Paired: v("b", false), Bonded: v("b", true), Connected: v("b", true) },
        "org.bluez.Battery1": { Percentage: v("y", 80) } },
    "/org/bluez/hci0/dev_CC": { "org.bluez.Device1": { Address: v("s", "CC:CC"), Alias: v("s", " "),
        Paired: v("b", false), Bonded: v("b", false), Connected: v("b", false) } },
}] });

const state = run(reply);
assert.equal(state.btOn, true);
assert.equal(state.btConnected, 1);
assert.equal(state.btConnectedName, "Buds");
assert.deepEqual(state.btDevices.map(d => [d.mac, d.name, d.connected, d.paired, d.bat]), [
    ["BB:BB", "Buds", true, true, "80"],        // connected first, bonded counts as paired
    ["AA:AA", "Speaker", false, true, ""],
    ["CC:CC", "CC:CC", false, false, ""],       // blank alias falls back to the address
]);

// bluetoothd stopped: busctl prints nothing
const off = run("");
assert.equal(off.btOn, false);
assert.equal(off.btConnected, 0);
assert.deepEqual(off.btDevices, []);
console.log("ok");
