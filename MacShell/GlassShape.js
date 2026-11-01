.pragma library

// Outline of the Dock's label / context-menu bubble (macOS Tahoe): a rounded rectangle with continuous-looking corners and,
// optionally, a small pointer tail under its bottom edge. The tail is one smooth wedge: concave "fillets" where it leaves the
// body and a rounded tip, exactly like the real thing.
//
//   ox, oy   where the body's top-left corner lies on the canvas
//   W, H     body size (the tail hangs BELOW H and is not part of it)
//   r        corner radius
//   tx       x of the tail's centre, relative to the body's left edge
//   tw, th   tail width at the body edge (fillets included) and its depth; th <= 0 = no tail
//   tr       radius of the tail tip
//
// cmds() describes the outline once; build() replays it on a Canvas 2D context (the caller fills / strokes / clips it) and
// svg() turns it into an SVG path string (for a QtQuick.Shapes PathSvg).
function cmds(ox, oy, W, H, r, tx, tw, th, tr) {
    var c = Math.max(0.5, Math.min(r * 1.12, W / 2, H / 2));      // corner length: a little longer than r = flatter, Apple-like corner
    var ck = c * 0.66;                                               // bezier handle length (0.5523 would be a plain circular arc)
    var o = [];
    o.push(["M", ox + c, oy]);
    o.push(["L", ox + W - c, oy]);
    o.push(["C", ox + W - c + ck, oy, ox + W, oy + c - ck, ox + W, oy + c]);
    o.push(["L", ox + W, oy + H - c]);
    o.push(["C", ox + W, oy + H - c + ck, ox + W - c + ck, oy + H, ox + W - c, oy + H]);

    if (th > 0 && tw > 0) {
        // The tail is a flat V with a rounded tip, blended into the body edge by a small fillet on each side:
        //   hb   half of the base, fillets included          hw0  where the straight sides would meet the body edge
        //   g    length of the tip rounding along a side     thA  depth of the (sharp) apex; the rounded tip ends up exactly th deep
        var hb = tw / 2;
        var hw0 = hb * 0.68;
        var f = hb - hw0;
        var g = Math.max(tr, 0.5) * 1.5;
        var thA = th, L = 1, ux = 0, uy = 1;
        for (var it = 0; it < 4; it++) {
            L = Math.sqrt(hw0 * hw0 + thA * thA);
            uy = thA / L;
            thA = th + 0.5 * g * uy;
        }
        L = Math.sqrt(hw0 * hw0 + thA * thA);
        ux = hw0 / L;
        uy = thA / L;
        var cx = ox + Math.max(c + hb, Math.min(W - c - hb, tx));    // never closer to a corner than the corner itself
        var by = oy + H;
        o.push(["L", cx + hb, by]);
        o.push(["Q", cx + hw0, by, cx + hw0 - ux * f, by + uy * f]);
        o.push(["L", cx + ux * g, by + thA - uy * g]);
        o.push(["Q", cx, by + thA, cx - ux * g, by + thA - uy * g]);
        o.push(["L", cx - hw0 + ux * f, by + uy * f]);
        o.push(["Q", cx - hw0, by, cx - hb, by]);
    }

    o.push(["L", ox + c, oy + H]);
    o.push(["C", ox + c - ck, oy + H, ox, oy + H - c + ck, ox, oy + H - c]);
    o.push(["L", ox, oy + c]);
    o.push(["C", ox, oy + c - ck, ox + c - ck, oy, ox + c, oy]);
    o.push(["Z"]);
    return o;
}

function build(ctx, ox, oy, W, H, r, tx, tw, th, tr) {
    var a = cmds(ox, oy, W, H, r, tx, tw, th, tr);
    ctx.beginPath();
    for (var i = 0; i < a.length; i++) {
        var s = a[i];
        if (s[0] === "M") ctx.moveTo(s[1], s[2]);
        else if (s[0] === "L") ctx.lineTo(s[1], s[2]);
        else if (s[0] === "C") ctx.bezierCurveTo(s[1], s[2], s[3], s[4], s[5], s[6]);
        else if (s[0] === "Q") ctx.quadraticCurveTo(s[1], s[2], s[3], s[4]);
        else ctx.closePath();
    }
}

function svg(ox, oy, W, H, r, tx, tw, th, tr) {
    var a = cmds(ox, oy, W, H, r, tx, tw, th, tr), out = "";
    for (var i = 0; i < a.length; i++) {
        var s = a[i];
        out += s[0];
        for (var j = 1; j < s.length; j++) out += (j > 1 ? " " : "") + s[j].toFixed(2);
        out += " ";
    }
    return out;
}
