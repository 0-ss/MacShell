#version 440
// "Burning paper" cover transition, without the fire: the old picture is eaten away along ragged, organic
// edges (holes open and spread like burning paper) and the new picture shows through. No embers, no colour change.
// Also clips both pictures to a rounded rectangle.
// Build:  /usr/lib/qt6/bin/qsb --qt6 -o burn.frag.qsb burn.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;     // 0 = old picture, 1 = new picture
    vec2 itemSize;      // px
    float radius;       // corner radius, px
    float seed;         // changes per transition, so every burn looks different
};

layout(binding = 1) uniform sampler2D oldTex;
layout(binding = 2) uniform sampler2D newTex;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p)
{
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
    return v;
}
float roundBox(vec2 q, vec2 hs, float r)
{
    vec2 d = abs(q) - (hs - r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void main()
{
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * itemSize;
    float cov = clamp(0.5 - roundBox(p - itemSize * 0.5, itemSize * 0.5, radius), 0.0, 1.0);

    // burn map: large ragged blobs (fbm) where the paper goes first, plus fine fibres along the edge
    vec2 np = uv * vec2(itemSize.x / itemSize.y, 1.0) * 3.2 + seed * 17.0;
    float m = fbm(np) * 0.82 + noise(np * 9.0) * 0.18;
    // spread the range so 0 → nothing burned, 1 → everything burned
    float t = progress * 1.25 - 0.12;
    float reveal = smoothstep(m - 0.05, m + 0.05, t);     // soft, ragged edge — no colour, just the shape

    vec4 o = texture(oldTex, uv), n = texture(newTex, uv);
    fragColor = mix(o, n, reveal) * cov * qt_Opacity;
}
