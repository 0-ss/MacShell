// Regression tests for known window-capture crash (wl_display invalid object) and wrong/stale frame bugs.
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";

const read = (rel) => readFileSync(new URL(rel, import.meta.url), "utf8");
const gateJs = read("../MacShell/CaptureGate.js");
const safeCapQml = read("../MacShell/SafeCapture.qml");
const glassCapQml = read("../MacShell/GlassCapture.qml");
const shellQml = read("../MacShell/shell.qml");
const dockQml = read("../MacShell/MacDock.qml");
const barQml = read("../MacShell/MacBar.qml");
const minFxQml = read("../MacShell/MinimizeFx.qml");

function extractFn(src, name) {
    const marker = `function ${name}(`;
    const sigStart = src.indexOf(marker);
    assert.ok(sigStart >= 0, `Could not find ${marker}`);
    const paramsStart = sigStart + marker.length;
    const paramsEnd = src.indexOf(")", paramsStart);
    const params = src.slice(paramsStart, paramsEnd).split(",").map((s) => s.trim()).filter(Boolean);
    const bodyStart = src.indexOf("{", paramsEnd);
    let depth = 0;
    for (let i = bodyStart; i < src.length; i++) {
        if (src[i] === "{") depth++;
        else if (src[i] === "}" && --depth === 0) return { params, body: src.slice(bodyStart + 1, i) };
    }
    throw new Error(`Unclosed function ${name}`);
}

// 1. No bare ScreencopyView anywhere outside SafeCapture.qml
{
    const qmlFiles = readdirSync(new URL("../MacShell", import.meta.url)).filter((f) => f.endsWith(".qml"));
    for (const file of qmlFiles) {
        if (file === "SafeCapture.qml") continue;
        const src = read(`../MacShell/${file}`);
        assert.doesNotMatch(src, /\bScreencopyView\s*\{/, `${file} must not instantiate bare ScreencopyView`);
    }
}

// 2. Destruction-order invariants: no ScreencopyView destroyed while held !== null
{
    // Dock thumbnail graceMs must be strictly shorter than leaveMs + 30 (leaveTimer)
    const leaveMatch = dockQml.match(/readonly property int leaveMs:\s*(\d+)/);
    const svBlock = dockQml.slice(dockQml.indexOf("id: sv"), dockQml.indexOf("id: sv") + 900);
    const graceMatch = svBlock.match(/graceMs:\s*(\d+)/);
    assert.ok(leaveMatch && graceMatch, "Expected leaveMs and sv.graceMs in MacDock.qml");
    const leaveMs = Number(leaveMatch[1]);
    const svGraceMs = Number(graceMatch[1]);
    assert.ok(svGraceMs < leaveMs, `Dock thumbnail graceMs (${svGraceMs}) must be < leaveMs (${leaveMs})`);
    assert.match(svBlock, /cell\.closingWin \|\| cell\.leavingCell\)\s*\?\s*null\s*:\s*cell\.heldTl/);
    assert.match(svBlock, /healOnResize:\s*false/);

    // Both MacDock and MacBar drain backdrops before unloading Loader
    assert.match(dockQml, /id:\s*glassBackdrop\s*\n\s*active:\s*root\.backdropLoaded/);
    assert.match(dockQml, /property bool backdropDraining:\s*false/);
    assert.match(barQml, /id:\s*glassBackdrop\s*\n\s*active:\s*root\.backdropLoaded/);
    assert.match(barQml, /id:\s*swBackdrop\s*\n\s*active:\s*root\.backdropLoaded/);
    assert.match(barQml, /id:\s*wpBackdrop\s*\n\s*active:\s*root\.backdropLoaded/);
    assert.match(barQml, /id:\s*osdBackdrop\s*\n\s*active:\s*root\.backdropLoaded/);
    assert.match(barQml, /id:\s*spotBackdrop\s*\n\s*active:\s*root\.backdropLoaded/);
    assert.match(barQml, /property bool backdropDraining:\s*false/);

    // Sweep timers in both MacDock and MacBar refuse to remove a delegate whose capture is still held
    assert.match(dockQml, /id:\s*sweep[\s\S]{0,400}it\.cap\.held !== null/);
    assert.match(barQml, /id:\s*sweep[\s\S]{0,400}it\.cap\.held !== null/);

    // Overlay backdrops in MacBar stay detached while hidden and only capture overlapping windows
    assert.match(barQml, /id:\s*spotBackdrop[\s\S]{0,500}spotWin\.openish && !root\.gaming/);
    assert.match(barQml, /id:\s*spotBackdrop[\s\S]{0,500}item\.regionOnly = true/);
    assert.match(barQml, /id:\s*swBackdrop[\s\S]{0,500}item\.regionOnly = true/);
    assert.match(barQml, /id:\s*wpBackdrop[\s\S]{0,500}item\.regionOnly = true/);
    assert.match(barQml, /id:\s*osdBackdrop[\s\S]{0,500}item\.regionOnly = true/);

    // MacBar burst() typo fixed (opt-in with === "1", not running by default via === "0")
    assert.match(barQml, /function burst\(\)\s*\{\s*if \(Quickshell\.env\("MACSHELL_BURST"\) !== "1"/);

    // shell.qml barHold pauses on storm and churn by default
    assert.match(shellQml, /readonly property bool barHold:.*storm.*churn && Quickshell\.env\("MACSHELL_CHURNPAUSE"\) !== "0"/);

    // MacDock glassRT respects glassHold/storm/churn
    assert.match(dockQml, /readonly property bool quiet:\s*root\.backdropDraining \|\| root\.glassHold/);

    // MinimizeFx disables resize heal
    assert.match(minFxQml, /healOnResize:\s*false/);
}

// 3. Wrong/stale frame invariants
{
    assert.match(glassCapQml, /readonly property bool hasContent:\s*cap\.hasContent === true && cap\.held !== null && cap\.held === cap\.want/);
    assert.match(glassCapQml, /visible:\s*on && glassCap\.keepValid/);
    assert.match(glassCapQml, /function onWantChanged\(\)[\s\S]{0,300}glassCap\.keepValid = false/);
    assert.match(dockQml, /readonly property bool thumbReady:\s*useThumb && !leavingCell && !closingWin && sv\.hasContent === true && sv\.held !== null && sv\.held === sv\.want/);
    assert.match(dockQml, /id:\s*gsv\s*\n\s*visible:\s*tearGhost\.isWin && gsv\.hasContent === true && gsv\.held === gsv\.want/);
    assert.match(barQml, /id:\s*screenSnap[\s\S]{0,600}hold:\s*root\.captureHeld \|\| root\.captureQuiet \|\| root\.backdropDraining/);
    assert.match(barQml, /function onGlassClientsChanged\(\)\s*\{\s*screenSnap\.takenAt = 0; ui\.snapFresh = false;\s*\}/);
}

// 4. Behavioral test: CaptureGate.js storm detection and slot spacing
{
    let now = 10_000;
    const FakeDate = { now: () => now };
    const gateBody = gateJs.replace(/^\.pragma library\s*/, "") + "\nreturn { noteFail, recentFails, isStorm, slotDelay };";
    const gate = new Function("Date", gateBody)(FakeDate);

    assert.equal(gate.isStorm(), false);
    gate.noteFail();
    gate.noteFail();
    gate.noteFail();
    assert.equal(gate.isStorm(), false, "3 failures should not trigger storm yet");
    gate.noteFail();
    assert.equal(gate.isStorm(), true, "4th failure within window must trigger storm immediately");
    assert.equal(gate.recentFails(2000), 4);

    // Storm persists for STORM_HOLD_MS (1200ms) even if no new fails arrive
    now += 1000;
    assert.equal(gate.isStorm(), true);
    now += 1500;
    assert.equal(gate.isStorm(), false, "storm must clear after window and hold expire");

    // slotDelay spaces out bursts
    const d1 = gate.slotDelay();
    const d2 = gate.slotDelay();
    const d3 = gate.slotDelay();
    assert.equal(d1, 0);
    assert.ok(d2 >= 45, `expected second slot >= 45ms, got ${d2}`);
    assert.ok(d3 >= 90, `expected third slot >= 90ms, got ${d3}`);
}

// 5. Behavioral test: shell.qml tlFor / tlSeed / tlPrune normalization & closingWins guard
{
    let now = 50_000;
    const FakeDate = { now: () => now };
    const tlSeedSpec = extractFn(shellQml, "tlSeed");
    const tlForSpec = extractFn(shellQml, "tlFor");
    const tlPruneSpec = extractFn(shellQml, "tlPrune");

    const tlA = { id: "A" };
    const tlB = { id: "B" };
    const Hyprland = {
        toplevels: {
            values: [
                { address: "0xAbC123", wayland: tlA },
                { address: "def456", wayland: tlB },
            ],
        },
    };
    const tlState = { ready: {}, last: 0, next: 0 };
    const closingWins = { def456: true };
    let armedCalls = 0;
    const Qt = { callLater: (fn) => { armedCalls++; fn(); } };
    const tlArm = () => {};

    const tlSeed = new Function("Hyprland", "tlState", "closingWins", "Date", tlSeedSpec.body);
    const tlFor = new Function(...tlForSpec.params, "Hyprland", "tlState", "closingWins", "Date", "Qt", "tlArm", tlForSpec.body);
    const tlPrune = new Function("Hyprland", "tlState", tlPruneSpec.body);

    tlSeed(Hyprland, tlState, closingWins, FakeDate);
    assert.ok(tlState.ready["abc123"] >= now + 220, "new window must wait >= 220ms before admission");
    assert.equal(tlState.ready["def456"], undefined, "closing window must never be seeded");

    // Closing window returns null regardless of 0x prefix or casing
    assert.equal(tlFor("0xDEF456", Hyprland, tlState, closingWins, FakeDate, Qt, tlArm), null);
    // Young window returns null and arms timer
    assert.equal(tlFor("0xABC123", Hyprland, tlState, closingWins, FakeDate, Qt, tlArm), null);
    assert.ok(armedCalls >= 1);

    // After admission delay, tlFor returns the wayland toplevel regardless of case/prefix
    now += 250;
    assert.equal(tlFor("abc123", Hyprland, tlState, closingWins, FakeDate, Qt, tlArm), tlA);

    // Once window disappears from Hyprland.toplevels, tlPrune removes normalized key
    Hyprland.toplevels.values = [];
    tlPrune(Hyprland, tlState);
    assert.equal(tlState.ready["abc123"], undefined);
}

// 6. Behavioral test: SafeCapture.qml attach() & recover() grace/storm safety
{
    let now = 100_000;
    const FakeDate = { now: () => now };
    const attachSpec = extractFn(safeCapQml, "attach");
    const recoverSpec = extractFn(safeCapQml, "recover");

    // attach() must wait graceMs when switching held -> different want while !ended, even if hadContent === true
    let attachInterval = -1;
    let attachRestarted = false;
    const st = {
        want: { id: 2 },
        held: { id: 1 },
        hadContent: true,
        ended: false,
        graceMs: 250,
    };
    const attachT = {
        set interval(v) { attachInterval = v; },
        restart() { attachRestarted = true; },
    };
    const Gate = { slotDelay: () => 0, noteFailCalls: 0, noteFail() { this.noteFailCalls++; } };
    const attach = new Function(
        "Gate", "attachT", "s",
        attachSpec.body.replace(/\b(want|held|ended|graceMs)\b/g, "s.$1"),
    );
    attach(Gate, attachT, st);
    assert.equal(attachRestarted, true, "switching active captureSource must be delayed by graceMs");
    assert.equal(attachInterval, 250);
    assert.deepEqual(st.held, { id: 1 }, "held must not be overwritten synchronously");

    // recover() must not double-count failures when ended === true, and must wait >= graceMs when !ended or recentSnap
    const rState = {
        want: { id: 1 },
        held: { id: 1 },
        reviving: false,
        dead: false,
        hold: false,
        tries: 0,
        maxTries: 3,
        ended: true,
        lastRebuild: 0,
        lastSnapAt: now - 500,
        graceMs: 250,
    };
    let reviveAInterval = -1;
    const reviveA = { set interval(v) { reviveAInterval = v; }, restart() {} };
    const wakeT = { restart() {} };
    const recover = new Function(
        ...recoverSpec.params,
        "Gate", "Date", "log", "wakeT", "reviveA", "s",
        recoverSpec.body.replace(
            /\b(want|held|reviving|dead|hold|tries|maxTries|ended|lastRebuild|lastSnapAt|graceMs)\b/g,
            "s.$1",
        ),
    );
    recover(true, Gate, FakeDate, () => {}, wakeT, reviveA, rState);
    assert.equal(Gate.noteFailCalls, 0, "recover() must not double-count when ended === true");
    assert.equal(reviveAInterval, 125);

    // Recent snap forces long grace period even when ended === true
    rState.reviving = false;
    rState.lastSnapAt = now - 20;
    recover(true, Gate, FakeDate, () => {}, wakeT, reviveA, rState);
    assert.equal(reviveAInterval, 400, "recent snap must get long grace period");

    // !ended notes failure once and uses >= 400ms grace
    rState.reviving = false;
    rState.ended = false;
    rState.lastSnapAt = 0;
    recover(false, Gate, FakeDate, () => {}, wakeT, reviveA, rState);
    assert.equal(Gate.noteFailCalls, 1);
    assert.equal(reviveAInterval, 400);
}

console.log("ok");
