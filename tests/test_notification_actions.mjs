// Tests notification action extraction, invocation, inline reply, and close/update cleanup in MacBar.qml.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const qml = readFileSync(new URL("../MacShell/MacBar.qml", import.meta.url), "utf8");

function extractFn(name) {
    const marker = `function ${name}(`;
    const sigStart = qml.indexOf(marker);
    assert.ok(sigStart >= 0, `Could not find ${marker}`);
    const paramsStart = sigStart + marker.length;
    const paramsEnd = qml.indexOf(")", paramsStart);
    const params = qml.slice(paramsStart, paramsEnd).split(",").map((s) => s.trim()).filter(Boolean);
    const bodyStart = qml.indexOf("{", paramsEnd);
    let depth = 0;
    for (let i = bodyStart; i < qml.length; i++) {
        if (qml[i] === "{") depth++;
        else if (qml[i] === "}" && --depth === 0) return { params, body: qml.slice(bodyStart + 1, i) };
    }
    throw new Error(`Unclosed function ${name}`);
}

const extractSpec = extractFn("notifExtractActions");
const invokeSpec = extractFn("notifInvokeAction");
const replySpec = extractFn("notifSendReply");
const startSpec = extractFn("notifStartReply");
const clearSpec = extractFn("notifClearReply");
const closedSpec = extractFn("notifHandleClosed");
const receiveSpec = extractFn("notifReceive");

const notifExtractActions = new Function(...extractSpec.params, extractSpec.body);
const notifStartReplyFn = new Function(...startSpec.params, "root", startSpec.body);
const notifClearReplyFn = new Function(...clearSpec.params, "root", clearSpec.body);
const notifHandleClosedFn = new Function(...closedSpec.params, "root", "notifToastRemove", "notifIndex", "notifHist", closedSpec.body);
const notifInvokeActionFn = new Function(...invokeSpec.params, "root", "notifToastRemove", invokeSpec.body);
const notifSendReplyFn = new Function(...replySpec.params, "root", "notifToastRemove", replySpec.body);
const notifReceiveFn = new Function(
    ...receiveSpec.params,
    "root", "Quickshell", "NotificationUrgency", "notifHist", "notifToasts", "notifIndex",
    receiveSpec.body,
);

function makeListModel() {
    const rows = [];
    return {
        rows,
        get count() { return rows.length; },
        get(i) { return rows[i]; },
        insert(i, rec) { rows.splice(i, 0, { ...rec }); },
        remove(i) { rows.splice(i, 1); },
        setProperty(i, role, val) { rows[i][role] = val; },
    };
}

function makeSignal() {
    const fns = [];
    return {
        connect(fn) { fns.push(fn); },
        emit() { for (const fn of fns) fn(); },
    };
}

// Filters out default, inline-reply, and blank actions while preserving named actions
{
    const extracted = notifExtractActions({
        actions: [
            { identifier: "default", text: "Open" },
            { identifier: "inline-reply", text: "Reply" },
            { identifier: "mark_read", text: "Mark as Read" },
            { identifier: "empty", text: "   " },
            { identifier: "snooze", text: "Snooze 10m" },
        ],
    });
    assert.deepEqual(extracted, [
        { id: "mark_read", text: "Mark as Read" },
        { id: "snooze", text: "Snooze 10m" },
    ]);
}

// Invoking a non-resident action calls invoke(), clears reply state, and removes the toast unless deferred
{
    const invoked = [];
    const removed = [];
    const root = {
        notifReplyNid: 7,
        notifClearReply(id) { notifClearReplyFn(id, root); },
        notifRefs: {
            7: {
                resident: false,
                actions: [
                    { identifier: "default", invoke: () => invoked.push("default") },
                    { identifier: "accept", invoke: () => invoked.push("accept") },
                ],
            },
        },
    };
    assert.equal(notifInvokeActionFn(7, "accept", false, root, (id) => removed.push(id)), true);
    assert.deepEqual(invoked, ["accept"]);
    assert.equal(root.notifReplyNid, -1);
    assert.deepEqual(removed, []);

    assert.equal(notifInvokeActionFn(7, "accept", undefined, root, (id) => removed.push(id)), true);
    assert.deepEqual(removed, [7]);
}

// Invoking a resident action calls invoke() without removing the toast
{
    const invoked = [];
    const removed = [];
    const root = {
        notifReplyNid: -1,
        notifClearReply(id) { notifClearReplyFn(id, root); },
        notifRefs: {
            9: {
                resident: true,
                actions: [{ identifier: "like", invoke: () => invoked.push("like") }],
            },
        },
    };
    assert.equal(notifInvokeActionFn(9, "like", undefined, root, (id) => removed.push(id)), true);
    assert.deepEqual(invoked, ["like"]);
    assert.deepEqual(removed, []);
}

// Inline reply trims text, rejects blanks, invokes sendInlineReply, clears reply state, and respects resident/removeToast
{
    const replies = [];
    const removed = [];
    const root = {
        notifReplyNid: 11,
        notifClearReply(id) { notifClearReplyFn(id, root); },
        notifRefs: {
            11: {
                resident: false,
                hasInlineReply: true,
                sendInlineReply: (t) => replies.push(t),
            },
        },
    };
    assert.equal(notifSendReplyFn(11, "   ", undefined, root, (id) => removed.push(id)), false);
    assert.equal(root.notifReplyNid, 11);
    assert.equal(notifSendReplyFn(11, "  On my way!  ", undefined, root, (id) => removed.push(id)), true);
    assert.deepEqual(replies, ["On my way!"]);
    assert.equal(root.notifReplyNid, -1);
    assert.deepEqual(removed, [11]);
}

// Closing a notification clears stale history actions/reply roles, cancels active reply, and drops notifRefs[id]
// Removing inline reply in-place clears active reply state so keyboard focus / toast timer never stick
{
    const hist = makeListModel();
    const toasts = makeListModel();
    const idxOf = (m, id) => m.rows.findIndex((r) => r.nid === id);
    const root = {
        notifSeq: 0,
        notifRefs: {},
        notifDnd: false,
        notifOpen: true,
        notifUnread: 0,
        notifReplyNid: -1,
        notifExtractActions,
        notifClearReply(id) { notifClearReplyFn(id, root); },
        notifToastRemove(id) { const i = idxOf(toasts, id); if (i >= 0) toasts.remove(i); },
        notifHandleClosed(id) { notifHandleClosedFn(id, root, root.notifToastRemove, idxOf, hist); },
        isSystemNotif: () => false,
        playSound: () => {},
    };
    const closedSig = makeSignal();
    const replyChangedSig = makeSignal();
    const n = {
        appName: "Chat",
        summary: "Alex",
        body: "Hey!",
        image: "",
        appIcon: "",
        urgency: 1,
        expireTimeout: 0,
        actions: [{ identifier: "mark_read", text: "Mark Read" }],
        hasInlineReply: true,
        inlineReplyPlaceholder: "Reply to Alex",
        closed: closedSig,
        summaryChanged: makeSignal(),
        bodyChanged: makeSignal(),
        actionsChanged: makeSignal(),
        hasInlineReplyChanged: replyChangedSig,
        inlineReplyPlaceholderChanged: makeSignal(),
    };
    notifReceiveFn(n, root, { iconPath: () => "" }, { Low: 0, Critical: 2 }, hist, toasts, idxOf);
    assert.equal(hist.count, 1);
    assert.equal(hist.get(0).hasReply, true);
    assert.equal(hist.get(0).actionsJson, JSON.stringify([{ id: "mark_read", text: "Mark Read" }]));

    // Simulate replying, then app removes inline reply in-place
    root.notifReplyNid = 1;
    n.hasInlineReply = false;
    replyChangedSig.emit();
    assert.equal(hist.get(0).hasReply, false);
    assert.equal(root.notifReplyNid, -1);

    // Re-enable reply and compose on DP-1, then app closes the notification
    n.hasInlineReply = true;
    replyChangedSig.emit();
    notifStartReplyFn(1, "DP-1", root);
    assert.equal(root.notifReplyNid, 1);
    assert.equal(root.notifReplyScreen, "DP-1");
    closedSig.emit();
    assert.equal(root.notifReplyNid, -1);
    assert.equal(root.notifReplyScreen, "");
    assert.equal(hist.get(0).actionsJson, "[]");
    assert.equal(hist.get(0).hasReply, false);
    assert.equal(hist.get(0).replyPlaceholder, "");
    assert.equal(root.notifRefs[1], undefined);
}

// Hidden monitor toast delegates must not run auto-dismiss timers or expire an active reply
{
    const timerBlock = qml.slice(qml.indexOf("interval: toast.life"), qml.indexOf("onTriggered: toast.dismiss()") + 30);
    const runMatch = timerBlock.match(/running:\s*(.+)/);
    assert.ok(runMatch, "toast auto-dismiss Timer running binding must exist");
    const timerRunning = new Function("toastArea", "toast", "thov", "root", `return (${runMatch[1]});`);
    // Hidden screen while active reply is open on another screen -> must NOT run
    assert.equal(timerRunning({ visible: false }, { shown: true, leaving: false, nid: 5 }, { hovered: false }, { notifReplyNid: 5 }), false);
    assert.equal(timerRunning({ visible: false }, { shown: true, leaving: false, nid: 5 }, { hovered: false }, { notifReplyNid: -1 }), false);
    // Visible screen while replying -> paused
    assert.equal(timerRunning({ visible: true }, { shown: true, leaving: false, nid: 5 }, { hovered: false }, { notifReplyNid: 5 }), false);
    // Visible screen after reply closes -> resumes
    assert.equal(timerRunning({ visible: true }, { shown: true, leaving: false, nid: 5 }, { hovered: false }, { notifReplyNid: -1 }), true);
}

console.log("ok");
