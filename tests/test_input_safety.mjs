// Input-boundary checks for MacBar.qml / Desktop.qml / MacDock.qml.   node tests/test_input_safety.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = f => readFileSync(new URL(`../MacShell/${f}`, import.meta.url), "utf8");
const [bar, dock, desktop] = ["MacBar.qml", "MacDock.qml", "Desktop.qml"].map(read);

// Pulls `function name(args) { ... }` out of QML by brace depth and returns it as a callable.
function extract(qml, name) {
    const at = qml.indexOf(`function ${name}(`);
    assert.ok(at >= 0, `${name} not found`);
    const open = qml.indexOf("{", at);
    let end = open + 1;
    for (let depth = 1; depth > 0; end++) depth += qml[end] === "{" ? 1 : qml[end] === "}" ? -1 : 0;
    return new Function(`return ${qml.slice(at, end)}`)();
}

const buildFocusLua = extract(bar, "buildFocusLua");
const ok = buildFocusLua({ addr: "0x55aa", ws: 3, cls: "kitty" });
assert.equal(ok, 'hl.dispatch(hl.dsp.focus({ workspace = "3" })); hl.dispatch(hl.dsp.focus({ window = "address:0x55aa" })); hl.dispatch(hl.dsp.window.bring_to_top())');
assert.match(buildFocusLua({ addr: "55aa", ws: 0, cls: "" }), /window = "address:0x55aa"/);   // missing 0x is added
assert.ok(!buildFocusLua({ addr: "55aa", ws: 0, cls: "" }).includes("workspace"));              // ws 0 means no workspace switch

// invalid address falls back to the escaped class
const bad = buildFocusLua({ addr: '0x1"); os.execute("id"); --', ws: "7; evil()", cls: "org.Foo" });
assert.ok(!bad.includes("address:") && !bad.includes("evil") && !bad.includes("workspace"));
assert.ok(bad.includes('class:^(org\\\\.Foo)$'));                                              // dot is a literal in the regex

// hostile class stays inside the Lua string literal
const evil = '"); os.execute("id"); --\n';
const lua = buildFocusLua({ addr: "", ws: 1, cls: evil });
assert.ok(!lua.includes("\n"));
const m = lua.match(/window = "((?:[^"\\]|\\.)*)" \}\)\)/);                                    // string body with escapes only
assert.ok(m, "class string literal is closed only by its own quote");
assert.ok(!/os\.execute\("id"\)/.test(lua.replace(/\\./g, "")));                              // every quote in the payload is backslash-escaped
assert.ok(lua.endsWith("hl.dispatch(hl.dsp.window.bring_to_top())"));

assert.equal(buildFocusLua({ addr: "", ws: 1, cls: "" }), "");
assert.equal(buildFocusLua({ addr: "zz", ws: 1 }), "");

const isValidFileName = extract(desktop, "isValidFileName");
for (const good of ["notes.txt", "my folder 2", ".hidden", "..x"]) assert.equal(isValidFileName(good), true, good);
for (const badName of ["", ".", "..", "../secret", "a/b", "foo\0bar"]) assert.equal(isValidFileName(badName), false, JSON.stringify(badName));

// `read -p` is a Bash extension; plain sh (dash) rejects it
for (const [name, qml] of [["MacBar.qml", bar], ["MacDock.qml", dock]])
    assert.ok(!/read\s+(-r\s+)?-p/.test(qml), `${name} still uses read -p`);
console.log("input safety ok");
