#version 440
// Liquid Glass for the Dock, tuned toward macOS Tahoe.
//
// Build:  qsb --qt6 -o dockglass.frag.qsb dockglass.frag
// (MacDock.qml runs this automatically and caches the result in ~/.config/macdock/. If the build fails the Dock keeps
//  using the shared liquidglass.frag, so nothing else in the shell depends on this file.)
//
// This is liquidglass.frag's refraction model (rounded-rect SDF -> convex bezel -> Snell's law -> dispersion) with the
// parts that make the Dock read as Tahoe glass reworked:
//   * edge: a crisp ~1 px specular line that is strong where the edge faces the light (top-left) and weaker on the far side,
//           a soft pooled glow just inside it, and a ~1 px dark line hugging the OUTSIDE of the edge so the glass stays
//           separated from bright wallpapers. Replaces the QML Canvas border, which repainted every frame while icons magnified.
//   * tint: adaptive - bright backdrops get more dark tint (so white icons / labels stay legible), dark backdrops get less,
//           instead of one flat tint amount.
//   * depth: the heavy dark inner edge is gone (Tahoe glass is clear, not smoked); only a faint absorption toward the edge stays.
//   * shadow: a wide ambient layer plus a tight contact layer, offset down, instead of one short 9 px falloff.
//
// Item padding (`pad`) must be >= 30 px so the ambient shadow is not clipped.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // whole shader item in px (glass + pad on every side)
    vec2 glassSize;     // the Dock rectangle in px
    vec2 srcSize;       // backdrop texture size in px
    vec2 srcOffset;     // where the item's top-left sits inside the backdrop texture, px
    float pad;          // item padding around the glass (room for the drop shadow)
    float radius;       // corner radius, px
    float bezel;        // width of the refracting rim, px
    float thickness;    // how far the rim shifts the backdrop, px
    float dispersion;   // chromatic split (0 = none)
    float blurPx;       // residual backdrop smoothing, px
    float tintMix;      // 0..1 base amount of flat tint (adapted to the backdrop below)
    float saturation;   // backdrop saturation boost
    float dark;         // 0 = light mode, 1 = dark mode
    float debug;        // 1 = show the raw backdrop texture (magenta = texture is empty)
    float rim;          // specular edge highlight strength
    float grain;        // fine noise amplitude over the whole glass
    float magnify;      // vertical lens magnification of the whole slab
    float shadowAmt;    // drop-shadow strength (1 = default, 0 = none)
    vec4 edgeTint;      // rgb = wallpaper's dominant colour (leans the edge light toward it), a = how strongly
};

layout(binding = 1) uniform sampler2D src;

const int   TAPS   = 24;
const float GOLDEN = 2.39996323;

// Same natural blur as liquidglass.frag: every tap reads a pre-blurred mip level sized to the gap between taps, Gaussian
// weights, and a per-pixel rotated pattern so leftover gaps turn into grain rather than ghost copies.
// Needs `mipmap: true` on the ShaderEffectSource.
vec3 backdropLod(vec2 pItem, float lod)
{
    vec2 uv = (pItem + srcOffset) / srcSize;
    return textureLod(src, clamp(uv, vec2(0.001), vec2(0.999)), lod).rgb;
}

float ign(vec2 p)
{
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

vec3 blurredDisp(vec2 pItem, vec2 disp, float disperse, float rad)
{
    float R   = max(rad, 0.5) * 1.5;
    float gap = R * sqrt(3.14159265 / float(TAPS));
    float lod = clamp(log2(max(gap, 1.0)) + 0.35, 0.0, 6.0);
    float rot = ign(gl_FragCoord.xy) * 6.2831853;
    vec3  acc = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < TAPS; ++i) {
        float fi = float(i) + 0.5;
        float r  = sqrt(fi / float(TAPS));
        float a  = fi * GOLDEN + rot;
        float w  = exp(-2.2 * r * r);
        vec2  o  = vec2(cos(a), sin(a)) * r * R;
        vec3  c;
        c.r = backdropLod(pItem + o + disp * (1.0 + disperse), lod).r;
        c.g = backdropLod(pItem + o + disp,                    lod).g;
        c.b = backdropLod(pItem + o + disp * (1.0 - disperse), lod).b;
        acc  += c * w;
        wsum += w;
    }
    return acc / wsum;
}

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float roundBox(vec2 q, vec2 hs, float r)
{
    vec2 d = abs(q) - (hs - r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void main()
{
    vec2 p  = qt_TexCoord0 * itemSize;
    vec2 hs = glassSize * 0.5;
    vec2 q  = p - vec2(pad) - hs;
    float r = min(radius, min(hs.x, hs.y));

    float sd  = roundBox(q, hs, r);               // < 0 inside the glass
    float cov = clamp(0.5 - sd, 0.0, 1.0);        // anti-aliased coverage

    if (debug > 0.5) {
        vec4 s = texture(src, clamp((p + srcOffset) / srcSize, vec2(0.001), vec2(0.999)));
        fragColor = (s.a < 0.01 ? vec4(1.0, 0.0, 1.0, 1.0) : vec4(s.rgb / max(s.a, 1e-3), 1.0)) * cov * qt_Opacity;
        return;
    }

    // ── outside the glass: nothing at all (no shadow, no dark outline) ──
    if (cov <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // ── distance to edge + outward edge direction ──
    float t = max(-sd, 0.0);
    vec2 d2 = abs(q) - (hs - r);
    vec2 sg = vec2(q.x >= 0.0 ? 1.0 : -1.0, q.y >= 0.0 ? 1.0 : -1.0);
    vec2 m  = max(d2, 0.0);
    vec2 g  = (length(m) > 1e-4) ? normalize(m) * sg
                                 : ((d2.x > d2.y) ? vec2(sg.x, 0.0) : vec2(0.0, sg.y));

    // ── convex squircle bezel -> surface normal ──
    float bz   = max(bezel, 1.0) * 1.45;
    float u    = clamp(t / bz, 0.0, 1.0);
    float om   = 1.0 - u;
    float om4  = om * om * om * om;
    float slope = (om * om * om) / pow(max(1.0 - om4, 1e-3), 0.75);
    slope = min(slope, 7.0);
    vec3 n = normalize(vec3(g * slope, 1.0));

    // ── refraction: glass n~1.5, ray enters straight down ──
    vec3 rd   = refract(vec3(0.0, 0.0, -1.0), n, 1.0 / 1.5);
    vec2 disp = rd.xy / max(-rd.z, 0.2) * thickness * 1.35;

    vec2 ps = vec2(p.x, (p.y - pad - hs.y) * (1.0 - magnify * 1.5) + pad + hs.y);
    float rad = blurPx * mix(0.45, 1.0, smoothstep(0.0, bz, t));

    vec3 col = blurredDisp(ps, disp, dispersion * 0.6, rad);

    // ── colour: vibrancy, then an ADAPTIVE tint ──
    float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(l), col, saturation);
    vec3 behind = col;                                            // the colour right behind this pixel, kept for the border below
    float lw    = smoothstep(0.30, 0.80, l);
    float adapt = mix(0.78, 1.28, mix(1.0 - lw, lw, dark));       // more tint where the backdrop would fight the icons
    vec3 tintC  = mix(vec3(1.0), vec3(0.09, 0.09, 0.10), dark);
    col = mix(col, tintC, clamp(tintMix * adapt, 0.0, 1.0));
    col += mix(0.055, 0.020, dark);

    // ── depth: soft light from above, faint absorption toward the edge (clear glass, not smoked) ──
    float ty = clamp((q.y + hs.y) / glassSize.y, 0.0, 1.0);
    col += (1.0 - ty) * mix(0.040, 0.034, dark);

    // ── edge light, from the top-left ──
    // identical to the top-bar menus (rimTint = 1): the rim / border take a darker shade of what the glass looks like at this spot
    vec3 rimCol   = clamp(col * 1.2, 0.0, 1.0);          // 120% of the glass colour (100% = natural) of the glass's own colour (menus use a brighter one: col * 1.5 + 0.12)

    vec2  L      = normalize(vec2(-0.55, -0.83));
    float facing = dot(g, L);
    float spec   = pow(max(facing, 0.0), 1.6) + 0.55 * pow(max(-facing, 0.0), 2.2);
    float crisp  = 1.0 - smoothstep(0.55, 1.55, t);                // the ~1 px line itself
    float pool   = exp(-t / 3.2);                                  // light pooling just inside it
    float edgeHi = crisp * (0.26 + 0.74 * spec) * 0.80 + pool * (0.05 + 0.10 * spec);
    edgeHi *= rim * 1.1 * mix(0.85, 1.0, dark);
    col += edgeHi * rimCol;

    // thin border line along the very edge, exactly as the menus draw it (ringW = 1 px here)
    float ringW = 1.0;
    float ring  = 1.0 - smoothstep(ringW * 0.5, ringW * 0.5 + 1.0, t);
    col = mix(col, rimCol, ring * (0.55 + 0.35 * clamp(facing * 0.5 + 0.5, 0.0, 1.0)));

    // meniscus: a very faint, wide second highlight inside the rim (kept soft so it never reads as an inner outline)
    float mx  = (t - bz * 0.5) / (bz * 0.35 + 1.0);
    float men = exp(-mx * mx);
    col += men * 0.03 * (0.35 + spec) * rim * rimCol;

    // fine triangular-distribution grain, same on every channel so it reads as texture, not colour noise
    float gn = hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0;
    col += gn * grain;

    col = clamp(col, 0.0, 1.0);

    // premultiplied: the glass over its own outer line / shadow (they only differ from zero in the 1 px anti-aliased band)
    fragColor = vec4(col * cov, cov) * qt_Opacity;
}
