// Unit tests for Roadmap #3 (Dock Folders/Stacks, Left/Right positioning, Badges, Recent Apps, Drag & Drop).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

function loadPragmaLib(relPath, exportsList) {
    const src = readFileSync(new URL(`../${relPath}`, import.meta.url), "utf8")
        .replace(/^\s*\.pragma\s+library\s*/m, "");
    return new Function(`${src}\nreturn { ${exportsList.join(", ")} };`)();
}

const DL = loadPragmaLib("MacShell/DockLogic.js", [
    "normalizePosition", "isVerticalPosition", "expandHome", "folderBaseName",
    "normalizeFolders", "updateRecentApps", "badgeCountFor", "formatBadgeText",
    "fanItemTransform", "buildOpenFilesArgs", "parseFolderListing"
]);

// Position helpers
assert.equal(DL.normalizePosition("left"), "left");
assert.equal(DL.normalizePosition("RIGHT"), "right");
assert.equal(DL.normalizePosition("invalid"), "bottom");
assert.equal(DL.isVerticalPosition("left"), true);
assert.equal(DL.isVerticalPosition("right"), true);
assert.equal(DL.isVerticalPosition("bottom"), false);

// Folder stacks
const folders = DL.normalizeFolders([
    { path: "~/Downloads", view: "fan" },
    "~/Documents",
    { path: "/home/u/Downloads", view: "grid" } // duplicate after expansion
], "/home/u");
assert.equal(folders.length, 2);
assert.equal(folders[0].path, "/home/u/Downloads");
assert.equal(folders[0].name, "Downloads");
assert.equal(folders[1].path, "/home/u/Documents");

const listing = DL.parseFolderListing("1700.0\tf\tphoto.png\n1600.0\td\tSub\n1500.0\tf\t.hidden\n", "/home/u/Downloads");
assert.equal(listing.length, 2);
assert.equal(listing[0].isImage, true);
assert.equal(listing[1].isDir, true);

const fan0 = DL.fanItemTransform(0, 5);
const fan4 = DL.fanItemTransform(4, 5);
assert.ok(fan4.offsetY < fan0.offsetY);
assert.ok(fan4.rotation < fan0.rotation);

// Recent apps
const rec = DL.updateRecentApps(["gimp", "vlc", "code"], ["firefox", "pinnedapp"], { pinnedapp: true }, { code: true }, 3);
assert.deepEqual(rec, ["firefox", "gimp", "vlc"]);

// Notification badges
assert.equal(DL.badgeCountFor({ kind: "app", key: "discord", appId: "discord", name: "Discord" }, { discord: 5 }, {}), 5);
assert.equal(DL.badgeCountFor({ kind: "app", key: "discord", appId: "discord", name: "Discord" }, { discord: 2 }, { discord: 9 }), 9);
assert.equal(DL.badgeCountFor({ kind: "app", key: "__trash", special: "trash" }, { trash: 3 }, {}), 0);
assert.equal(DL.formatBadgeText(0), "");
assert.equal(DL.formatBadgeText(7), "7");
assert.equal(DL.formatBadgeText(120), "99+");

// Open dropped files safely (no shell injection, strips %U/%F)
const args = DL.buildOpenFilesArgs("code --reuse-window %F", ["file:///tmp/my%20file.txt", "/tmp/b.md"]);
assert.deepEqual(args, ["sh", "-c", 'code --reuse-window "$@"', "sh", "/tmp/my file.txt", "/tmp/b.md"]);
assert.equal(DL.buildOpenFilesArgs("code %F", []), null);

// Static wiring & perf guards
const dockQml = readFileSync(new URL("../MacShell/MacDock.qml", import.meta.url), "utf8");
assert.ok(dockQml.includes("dockPosition") && dockQml.includes("isVertical"), "Vertical Dock positioning missing");
assert.ok(dockQml.includes("stackPopLoader") && dockQml.includes("fanItemTransform"), "Dock Folder Stacks missing");
assert.ok(dockQml.includes("badgePill") && dockQml.includes("badgeCountFor"), "Dock notification badges missing");
assert.ok(dockQml.includes("recentApps") && dockQml.includes("sep:recent"), "Recent Apps section missing");
assert.ok(dockQml.includes("DropArea") && dockQml.includes("dropFilesOnApp"), "Dock Drag & Drop missing");
assert.ok(dockQml.includes("live: menu.visible && root.liquidActive"), "Dock menu glass must be gated on menu.visible");

const deskQml = readFileSync(new URL("../MacShell/Desktop.qml", import.meta.url), "utf8");
assert.ok(deskQml.includes("appDropHit") && deskQml.includes("dropFilesOnApp"), "Desktop -> Dock app drop wiring missing");

console.log("ok");
