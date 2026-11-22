// Checks MacLock/I18n.js: ru and es define the same keys with non-empty strings.
import fs from "node:fs";
import assert from "node:assert/strict";

const src = fs.readFileSync(new URL("../MacLock/I18n.js", import.meta.url), "utf8").replace(/^\.pragma library/m, "");
const dicts = new Function(src + ";return dicts;")();

assert.ok(dicts.ru && dicts.es, "ru and es must both exist");
const ruKeys = Object.keys(dicts.ru).sort();
assert.deepEqual(Object.keys(dicts.es).sort(), ruKeys, "ru and es key sets differ");
for (const lang of ["ru", "es"])
    for (const [k, v] of Object.entries(dicts[lang]))
        assert.ok(typeof v === "string" && v !== "", `${lang}: empty value for ${JSON.stringify(k)}`);
console.log(`ok: ru/es share ${ruKeys.length} keys`);
