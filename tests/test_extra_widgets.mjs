// Verifies all ExtraWidgets types are registered in MacWidgets and Settings, and interactive ones capture clicks.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (rel) => readFileSync(new URL(rel, import.meta.url), "utf8");
const extraQml = read("../MacShell/ExtraWidgets.qml");
const widgetsQml = read("../MacShell/MacWidgets.qml");
const settingsQml = read("../MacShell/SettingsWindow.qml");

const compMatch = extraQml.match(/function comp\(type\)\s*\{\s*return \(\{([^}]+)\}\)\[type\]/);
assert.ok(compMatch, "ExtraWidgets.comp(type) mapping must exist");
const extraTypes = [...compMatch[1].matchAll(/(\w+)\s*:/g)].map((m) => m[1]);
assert.deepEqual(
    extraTypes.slice().sort(),
    ["alarms", "batteries", "notes", "photos", "reminders", "stocks"],
);

const typeNamesMatch = widgetsQml.match(/readonly property var typeNames:\s*\(\{([\s\S]*?)\}\)/);
assert.ok(typeNamesMatch, "MacWidgets.typeNames must exist");
const typeNames = new Set([...typeNamesMatch[1].matchAll(/(\w+)\s*:/g)].map((m) => m[1]));

const addBlockStart = settingsQml.indexOf('I18n.tr("Add a Widget")');
assert.ok(addBlockStart > 0, "Add a Widget section must exist in SettingsWindow.qml");
const addBlock = settingsQml.slice(addBlockStart, settingsQml.indexOf("delegate: Item", addBlockStart));
const dockTypes = new Set([...addBlock.matchAll(/type:\s*"(\w+)"/g)].map((m) => m[1]));

for (const t of extraTypes) {
    assert.ok(typeNames.has(t), `MacWidgets.typeNames is missing extra widget "${t}"`);
    assert.ok(dockTypes.has(t), `MacDock Settings Add-a-Widget list is missing "${t}"`);
}

const interMatch = widgetsQml.match(/function isInteractive\(type\)\s*\{([\s\S]*?)\}/);
assert.ok(interMatch, "MacWidgets.isInteractive(type) must exist");
const isInteractive = new Function("type", interMatch[1]);
for (const t of ["player", "reminders", "gif", "notes", "photos", "alarms"]) {
    assert.equal(isInteractive(t), true, `"${t}" must be interactive`);
}
assert.equal(isInteractive("weather"), false);
assert.equal(isInteractive("stocks"), false);

console.log("ok");
