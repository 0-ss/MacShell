#version 440
// Contour glow (Spotlight hover): a crisp light line that follows the rounded outline, plus a soft halo,
// brightest where the cursor is.
// Build:  /usr/lib/qt6/bin/qsb --qt6 -o contourglow.frag.qsb contourglow.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // this item in px (shape + pad on every side)
    vec2 mouse;         // cursor in shape coordinates (0,0 = shape's top-left)
    float pad;          // room around the shape for the halo
    float cornerR;      // shape corner radius
    float amount;       // 0..1 hover fade
    float spread;       // how far the bright spot reaches, px
    vec4 tint;          // glow colour (rgb)
};

float sdRoundRect(vec2 p, vec2 halfSize, float r)
{
    vec2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main()
{
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 c = itemSize * 0.5;
    float d = sdRoundRect(p - c, c - pad, cornerR);      // 0 on the outline, < 0 inside

    // everything stays INSIDE the shape: a crisp line just inside the outline (anti-aliased over ~0.6 px at the
    // edge) and a faint inner sheen — no halo spilling outside
    float inside = 1.0 - smoothstep(-0.3, 0.6, d);
    float line = exp(-max(-d, 0.0) / 1.0) * inside;
    float halo = exp(min(d, 0.0) / 5.0) * 0.14 * inside;

    // the part of the outline nearest the cursor lights up most; the rest keeps a faint glow
    float near = exp(-length(p - (mouse + pad)) / spread);
    float a = (line * 0.95 + halo) * mix(0.18, 1.0, near) * amount;

    fragColor = vec4(tint.rgb * a, a) * qt_Opacity;
}
