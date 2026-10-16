#version 440
// The lock screen clock's material, after iOS 26 / macOS 26:
//
//   Solid (mode 0) — Apple's vibrancy: the digits are the wallpaper behind them pushed most of the way to the tint
//                     colour (white by default), so they glow with a hint of the background's colour. Crisp, no rim.
//   Glass (mode 1) — Liquid Glass: clear, slightly frosted digits with real thickness. The wallpaper is bent at the
//                     rounded edges (strongest right at the edge), a bright glint runs along the edges facing the light
//                     and a softer one on the opposite side (light passing through the glass), a fine darker line just
//                     inside the edge gives the glass its definition. `lightDir` follows the pointer, like tilting a phone.
//
// `mask` = sharp glyph coverage; `hmap` = a lightly blurred copy whose slope finds the rim.
// Build:  /usr/lib/qt6/bin/qsb --qt6 -o glasstext.frag.qsb glasstext.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // this item in px
    vec2 srcSize;       // backdrop texture size in px (logical)
    vec2 srcOffset;     // this item's top-left inside the backdrop, px
    float mode;         // 0 solid … 1 glass (animatable: styles cross-fade)
    float intensity;    // solid: how far toward the tint (0.55‥0.95); glass: frost amount (0 clear … 1 milky)
    float refract;      // glass: backdrop shift at the very edge, px
    float bevel;        // rim slope scale
    vec4 tint;          // tint colour (white = none)
    vec2 lightDir;      // direction the light comes FROM (screen space, normalised)
};

layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D mask;
layout(binding = 3) uniform sampler2D hmap;

float H(vec2 uv) { return texture(hmap, uv).a; }
vec3 bgAt(vec2 p, float lod) { return textureLod(src, clamp(p / srcSize, vec2(0.001), vec2(0.999)), lod).rgb; }

void main()
{
    vec2 uv = qt_TexCoord0;
    float a = texture(mask, uv).a;
    if (a <= 0.002) { fragColor = vec4(0.0); return; }

    // rim from the slope of the softened glyphs: 0 in the flat middle of a stroke, 1 at the edge
    vec2 d = 1.5 / itemSize;
    vec2 g = vec2(H(uv + vec2(d.x, 0.0)) - H(uv - vec2(d.x, 0.0)),
                  H(uv + vec2(0.0, d.y)) - H(uv - vec2(0.0, d.y)));
    float slope = length(g);
    float rim = clamp(slope * bevel, 0.0, 1.0);
    vec2 n = slope > 1e-5 ? -g / slope : vec2(0.0);     // points out of the glyph
    vec2 p = uv * itemSize + srcOffset;
    vec3 tintC = tint.rgb;

    // ── Solid: vibrancy ──
    vec3 bgS = bgAt(p, 2.0);
    float ls = dot(bgS, vec3(0.299, 0.587, 0.114));
    bgS = mix(vec3(ls), bgS, 1.35);                      // keep the wallpaper's hue in it
    vec3 solid = mix(bgS, tintC, clamp(intensity, 0.0, 1.0)) + 0.04;

    // ── Glass ──
    // edge bending: a rounded edge bends the light most where it is steepest
    float bend = rim * rim * (3.0 - 2.0 * rim);
    vec2 shift = n * refract * bend;
    float lod = 0.6 + 2.2 * intensity;
    vec3 bg;
    bg.r = bgAt(p - shift * 1.08, lod).r;
    bg.g = bgAt(p - shift, lod).g;
    bg.b = bgAt(p - shift * 0.92, lod).b;
    float lg = dot(bg, vec3(0.299, 0.587, 0.114));
    bg = mix(vec3(lg), bg, 1.2);
    vec3 glass = bg * 1.05 + 0.05;
    glass = mix(glass, mix(vec3(1.0), tintC, 0.85), 0.10 + 0.55 * intensity);   // frost (and tint)
    glass = mix(glass, glass * tintC, 0.35 * (1.0 - tintC.r * tintC.g * tintC.b));  // coloured glass when tinted
    float facing = dot(n, normalize(lightDir));
    float edge = pow(rim, 2.2);
    glass += edge * pow(max(facing, 0.0), 1.5) * 0.85;              // glint on the lit edges
    glass += edge * pow(max(-facing, 0.0), 2.0) * 0.30;             // light through the glass, far side
    glass += pow(rim, 5.0) * 0.18;                                  // a hairline all round
    glass -= smoothstep(0.35, 0.75, rim) * (1.0 - smoothstep(0.75, 1.0, rim)) * 0.10;  // definition line inside the edge

    vec3 col = mix(solid, glass, clamp(mode, 0.0, 1.0));
    fragColor = vec4(clamp(col, 0.0, 1.0) * a, a) * qt_Opacity;
}
