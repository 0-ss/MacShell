// Runs the IpcHandler state() body from MacLock/shell.qml on mock lock states.   node tests/test_maclock_ipc_state.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const qml = readFileSync(new URL("../MacLock/shell.qml", import.meta.url), "utf8");
assert.match(qml, /WlSessionLock \{\s*id: sessionLock\b/);   // "lock" would be shadowed by the IPC method of the same name
assert.doesNotMatch(qml, /id: lock\b/);
assert.match(qml, /function lock\(\): void/);

const start = qml.indexOf("{", qml.indexOf("function state(): string")) + 1;
let end = start;
for (let depth = 1; depth > 0; end++) depth += qml[end] === "{" ? 1 : qml[end] === "}" ? -1 : 0;
const state = new Function("root", "sessionLock", qml.slice(start, end - 1));

const run = (wasSecure, secure, lockRequested) => state({ lockRequested }, { wasSecure, secure });
assert.equal(run(false, false, false), "ready");
assert.equal(run(false, false, true), "busy");
assert.equal(run(true, true, true), "busy");
assert.equal(run(true, false, false), "stopping");
