// Runs buildKeyCommand from MacBar.qml.   node tests/test_keys_dispatch.mjs
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, writeFileSync, chmodSync, readFileSync as rf, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const qml = readFileSync(new URL("../MacShell/MacBar.qml", import.meta.url), "utf8");
const head = qml.indexOf("function buildKeyCommand(");
const start = qml.indexOf("{", qml.indexOf(")", head)) + 1;
let end = start;
for (let depth = 1; depth > 0; end++) depth += qml[end] === "{" ? 1 : qml[end] === "}" ? -1 : 0;
const build = new Function("mods", "k", "rawAddr", qml.slice(start, end - 1));

const a = build(["ctrl", "shift"], "v", "deadbeef");
assert.ok(a.luaExpr.includes('mods = "CTRL SHIFT"'));
assert.ok(a.luaExpr.includes('key = "v"'));
assert.ok(a.luaExpr.includes('window = "address:0xdeadbeef"'));
assert.ok(a.focusLua.includes("address:0xdeadbeef"));
assert.deepEqual(a.wtypeArgs, ["-M", "ctrl", "-M", "shift", "-k", "v", "-m", "shift", "-m", "ctrl"]);

const b = build(["ctrl"], "comma", "");
assert.ok(!b.luaExpr.includes("window ="));
assert.ok(b.legacyArg.endsWith("activewindow"));
assert.equal(b.focusLua, "");

// a hostile window address never reaches the Lua expression
assert.ok(!build(["ctrl"], "v", "0x1; os.execute('id')").luaExpr.includes("window ="));
assert.equal(build(["ctrl"], "v; rm -rf /", "0x1"), null);
assert.equal(build(["ctrl; x"], "v", "0x1"), null);

// every key the menus use is accepted
for (const k of ["F5", "F12", "0", "equal", "minus"]) assert.ok(build([], k, ""), k);

// The real shell snippet from keys() against stub hyprctl/wtype: the fallback must fire when hyprctl exits 0 but prints no "ok".
const keysAt = qml.indexOf("function keys(");
const snippet = /"sh", "-c", '([^']+)'/.exec(qml.slice(keysAt, keysAt + 1500))[1];
function runKeys(hyprOut) {
    const dir = mkdtempSync(join(tmpdir(), "keys-"));
    const stub = (name, body) => { writeFileSync(join(dir, name), `#!/bin/sh\n${body}\n`); chmodSync(join(dir, name), 0o755); };
    stub("hyprctl", `echo "hyprctl $*" >> "${dir}/log"; echo '${hyprOut}'`);
    stub("wtype", `echo "wtype $*" >> "${dir}/log"`);
    const c = build(["ctrl"], "v", "deadbeef");
    spawnSync("sh", ["-c", snippet, "sh", c.luaExpr, c.legacyArg, c.focusLua, ...c.wtypeArgs], { env: { ...process.env, PATH: `${dir}:${process.env.PATH}` } });
    return existsSync(join(dir, "log")) ? rf(join(dir, "log"), "utf8") : "";
}
const bad = runKeys("Invalid dispatcher");
assert.ok(bad.includes("hyprctl dispatch sendshortcut") && bad.includes("wtype -M ctrl"), bad);
const good = runKeys("ok");
assert.ok(!good.includes("wtype") && !good.includes("sendshortcut"), good);
console.log("ok");
