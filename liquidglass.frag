#version 440
// Liquid Glass for the macdock Dock.
//
// Build:  qsb --qt6 -o liquidglass.frag.qsb liquidglass.frag
// (shell.qml runs this automatically on first use and caches the result in ~/.config/macdock/)
//
// The shader treats the Dock as a slab of curved glass sitting on top of a live backdrop texture:
//   * a rounded-rect signed distance field gives the distance to the edge and the edge direction
//   * a convex "squircle" bezel profile turns that into a surface normal
//   * Snell's law (refract) turns the normal into a lateral shift of the sampled backdrop
//   * the backdrop is sampled per colour channel (dispersion) through a small disk blur
//   * saturation / tint / milky lift, then specular rim, inner depth shading and a soft drop shadow

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
    float blurPx;       // backdrop blur radius, px
    float tintMix;      // 0..1 amount of flat tint (the "translucency" slider)
    float saturation;   // backdrop saturation boost
    float dark;         // 0 = light mode, 1 = dark mode
    float debug;        // 1 = show the raw backdrop texture (magenta = texture is empty)
    float rim;          // specular edge highlight strength (1 = original strength)
    float grain;        // fine noise amplitude over the whole glass
    float magnify;      // vertical lens magnification of the whole slab
    float shadowAmt;    // drop-shadow strength (1 = original, 0 = none) - appended last so older layouts stay compatible
};

layout(binding = 1) uniform sampler2D src;

const int   TAPS   = 10;
const float GOLDEN = 2.39996323;

vec3 backdrop(vec2 pItem)
{
    vec2 uv = (pItem + srcOffset) / srcSize;
    return texture(src, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
}

vec3 blurred(vec2 pItem, float rad)
{
    vec3 acc = vec3(0.0);
    for (int i = 0; i < TAPS; ++i) {
        float fi = float(i) + 0.5;
        float r  = sqrt(fi / float(TAPS));
        float a  = fi * GOLDEN;
        acc += backdrop(pItem + vec2(cos(a), sin(a)) * r * rad);
    }
    return acc / float(TAPS);
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

    // ── soft drop shadow (only visible outside the glass) ──
    float sds    = roundBox(q - vec2(0.0, 3.0), hs, r);
    float shadow = 0.30 * shadowAmt * (1.0 - smoothstep(-2.0, 9.0, sds));
    if (sd > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, shadow) * qt_Opacity;
        return;
    }

    // ── distance to edge + outward edge direction ──
    float t = max(-sd, 0.0);
    vec2 d2 = abs(q) - (hs - r);
    vec2 sg = vec2(q.x >= 0.0 ? 1.0 : -1.0, q.y >= 0.0 ? 1.0 : -1.0);
    vec2 m  = max(d2, 0.0);
    vec2 g  = (length(m) > 1e-4) ? normalize(m) * sg
                                 : ((d2.x > d2.y) ? vec2(sg.x, 0.0) : vec2(0.0, sg.y));

    // ── convex squircle bezel → surface normal ──
    float u    = clamp(t / max(bezel, 1.0), 0.0, 1.0);
    float om   = 1.0 - u;
    float om4  = om * om * om * om;
    float slope = (om * om * om) / pow(max(1.0 - om4, 1e-3), 0.75);
    slope = min(slope, 7.0);
    vec3 n = normalize(vec3(g * slope, 1.0));

    // ── refraction: glass n≈1.5, ray enters straight down ──
    vec3 rd   = refract(vec3(0.0, 0.0, -1.0), n, 1.0 / 1.5);
    vec2 disp = rd.xy / max(-rd.z, 0.2) * thickness;

    // the whole slab acts as a gentle vertical lens; blur is crisper right at the curved rim
    vec2 ps = vec2(p.x, (p.y - pad - hs.y) * (1.0 - magnify) + pad + hs.y);
    float rad = blurPx * mix(0.45, 1.0, smoothstep(0.0, max(bezel, 1.0), t));

    vec3 col;
    if (dispersion > 0.0) {
        col.r = blurred(ps + disp * (1.0 + dispersion), rad).r;
        col.g = blurred(ps + disp,                      rad).g;
        col.b = blurred(ps + disp * (1.0 - dispersion), rad).b;
    } else {
        col = blurred(ps + disp, rad);
    }

    // ── colour grading: vibrancy, tint, milky lift ──
    float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(l), col, saturation);
    vec3 tintC = mix(vec3(1.0), vec3(0.09, 0.09, 0.10), dark);
    col = mix(col, tintC, tintMix);
    col += mix(0.055, 0.020, dark);

    // ── depth: soft top sheen, darker lower inner edge ──
    float ty = clamp((q.y + hs.y) / glassSize.y, 0.0, 1.0);
    col += (1.0 - ty) * mix(0.040, 0.030, dark);
    col *= 1.0 - 0.12 * exp(-t / 6.0) * clamp(g.y, 0.0, 1.0);

    // ── specular rim, light from the top-left ──
    vec2  L      = normalize(vec2(-0.55, -0.83));
    float facing = dot(g, L);
    float spec   = pow(max(facing, 0.0), 1.6) + 0.55 * pow(max(-facing, 0.0), 2.2);
    float hair   = exp(-t / 1.1);
    float wide   = exp(-t / 5.0);
    float edgeHi = hair * (0.18 + 0.78 * spec) + wide * 0.10 * (0.30 + spec);
    edgeHi *= rim * mix(0.85, 1.0, dark);
    col += edgeHi * vec3(0.96, 0.98, 1.0);

    // fine triangular-distribution grain, same on every channel so it reads as texture, not colour noise
    float gn = hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0;
    col += gn * grain;

    col = clamp(col, 0.0, 1.0);

    float a = cov + shadow * (1.0 - cov);
    fragColor = vec4(col * cov, a) * qt_Opacity;   // premultiplied alpha
}
