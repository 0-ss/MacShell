.pragma library
// CaptureGate: shared bookkeeping for every window capture in the shell (one instance for the whole config, because of .pragma library).
//
// Why: the Wayland connection dies ("wl_display#1: error 0: invalid object NN") when a capture frame is torn down while Hyprland has
// already dropped it (a window re-tiled or closed under a running capture). Every capture that is created, fails and is rebuilt is one more
// chance for that. So the shell
//   * creates capture contexts one at a time, a few ms apart, instead of dozens in the same instant (slotDelay), and
//   * notices a "storm" (many captures failing within a couple of seconds, i.e. the layout is changing) and lets every live stream and
//     every single-shot sit out until it is over (recentFails, read by shell.qml -> hub.storm).

var _fails = [];
var _nextSlot = 0;
var _stormUntil = 0;
var SLOT_MS = 45;
var STORM_WINDOW_MS = 2000;
var STORM_FAILS = 4;
var STORM_HOLD_MS = 1200;

// a capture lost its picture / failed to get one
function noteFail() {
    var n = Date.now();
    _fails.push(n);
    if (_fails.length > 64) _fails.shift();
    if (recentFails(STORM_WINDOW_MS) >= STORM_FAILS) _stormUntil = Math.max(_stormUntil, n + STORM_HOLD_MS);
}

// how many captures failed in the last `ms`
function recentFails(ms) {
    var n = Date.now(), c = 0;
    for (var i = _fails.length - 1; i >= 0; i--) {
        if (n - _fails[i] <= ms) c++; else break;
    }
    return c;
}

// true immediately once failures spike (without waiting for a polling timer)
function isStorm() {
    var n = Date.now();
    if (n < _stormUntil) return true;
    if (recentFails(STORM_WINDOW_MS) >= STORM_FAILS) { _stormUntil = n + STORM_HOLD_MS; return true; }
    return false;
}

// how long a capture that wants a context NOW has to wait so that contexts are created at least SLOT_MS apart
function slotDelay() {
    var n = Date.now();
    var at = Math.max(n, _nextSlot);
    _nextSlot = at + SLOT_MS;
    return at - n;
}
