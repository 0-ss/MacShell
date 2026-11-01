#version 440
// The lock screen clock's material, after iOS 26 / macOS 26:
//
//   Solid (mode 0) — Apple's vibrancy: the digits are the wallpaper behind them pushed most of the way to the tint
//                     colour (white by default), so they glow with a hint of the background's colour. Crisp, no rim.
//   Glass (mode 1) — Liquid Glass: clear digits that are a real slab of glass. The blurred glyph coverage (`hmap`) is
//                     used as a height field: its slope is the surface normal, and the wallpaper behind is REFRACTED
//                     through that surface — bent most where the glass curves, undisturbed in the flat middle — with a
//                     touch of chromatic dispersion, a little magnification, and a faint frost. The light only shades
//                     the curved surface (brighter on the side facing it, darker on the other); there are NO outlines,
//                     rims, glints or hairlines anywhere. `lightDir` follows the pointer, like tilting a phone.
//
// `mask` = sharp glyph coverage; `hmap` = a softened copy that serves as the height field.
// Build:  /usr/lib/qt6/bin/qsb --qt6 -o glasstext.frag.qsb glasstext.frag      (or run ./build-shaders.sh)

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
    float refract;      // glass: strongest backdrop shift (on the steepest part of the bevel), px
    float bevel;        // height-field slope scale (how quickly the bend builds up)
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

    vec2 p = uv * itemSize + srcOffset;
    vec3 tintC = tint.rgb;

    // ── Solid: vibrancy ──
    vec3 bgS = bgAt(p, 2.0);
    float ls = dot(bgS, vec3(0.299, 0.587, 0.114));
    bgS = mix(vec3(ls), bgS, 1.35);                      // keep the wallpaper's hue in it
    vec3 solid = mix(bgS, tintC, clamp(intensity, 0.0, 1.0)) + 0.04;

    // ── Glass: refraction through a height field ──
    // surface slope (per px) from the softened glyphs: 0 on the flat top of a stroke, steepest on the curved flanks
    vec2 d = 2.0 / itemSize;
    vec2 g = vec2(H(uv + vec2(d.x, 0.0)) - H(uv - vec2(d.x, 0.0)),
                  H(uv + vec2(0.0, d.y)) - H(uv - vec2(0.0, d.y))) * 0.5;
    float slope = length(g) * bevel;
    float s = clamp(slope, 0.0, 1.0);
    vec2 n2 = slope > 1e-6 ? -g / length(g) : vec2(0.0);   // surface normal, projected: points out of the glyph

    // Snell-style bend: the ray is displaced along the slope (inwards where the glass falls away). A smooth S-curve
    // keeps the bend gradual across the whole bevel instead of piling up at the very edge.
    float bend = s * s * (3.0 - 2.0 * s);
    vec2 shift = n2 * refract * (0.35 * s + 0.65 * bend);
    float lod = 0.5 + 2.0 * intensity;
    vec3 bg;
    bg.r = bgAt(p - shift * 1.10, lod).r;               // dispersion: red bends least, blue most
    bg.g = bgAt(p - shift,        lod).g;
    bg.b = bgAt(p - shift * 0.90, lod).b;
    float lg = dot(bg, vec3(0.299, 0.587, 0.114));
    bg = mix(vec3(lg), bg, 1.25);                        // glass saturates what it bends
    vec3 glass = bg * 1.04 + 0.04;
    glass = mix(glass, mix(vec3(1.0), tintC, 0.85), 0.08 + 0.52 * intensity);        // frost (and tint)
    glass = mix(glass, glass * tintC, 0.35 * (1.0 - tintC.r * tintC.g * tintC.b));   // coloured glass when tinted

    // light only SHADES the curved surface: lit flank brighter, far flank darker, flat middle untouched
    float facing = dot(n2, normalize(lightDir));
    float shade = facing * smoothstep(0.0, 0.55, s);
    glass *= 1.0 + 0.22 * shade;
    glass += 0.10 * max(shade, 0.0) * (1.0 - 0.5 * intensity);

    vec3 col = mix(solid, glass, clamp(mode, 0.0, 1.0));
    fragColor = vec4(clamp(col, 0.0, 1.0) * a, a) * qt_Opacity;
}
