#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float power;
    float box;
    float soft;
    vec4 radii;
    float fillCorner;
};

layout(binding = 1) uniform sampler2D source;

float shapeSd(vec2 p, vec2 hs)
{
    if (power > 2.01) {
        vec2 a = max(abs(p) / hs, vec2(1e-4));
        float f = pow(a.x, power) + pow(a.y, power);
        float F = pow(f, 1.0 / power) - 1.0;
        vec2 g = pow(f, 1.0 / power - 1.0) * pow(a, vec2(power - 1.0)) / hs;
        return max(F / max(length(g), 1e-4), -min(hs.x, hs.y));
    }
    float r = p.x < 0.0 ? (p.y < 0.0 ? radii.x : radii.w) : (p.y < 0.0 ? radii.y : radii.z);
    r = min(r * 2.0 * hs.x, min(hs.x, hs.y));
    vec2 q = abs(p) - hs + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main()
{
    vec4 c = texture(source, qt_TexCoord0);
    if (fillCorner > 0.5 && c.a < 0.999) {
        vec4 f = texture(source, qt_TexCoord0 + (vec2(0.5) - qt_TexCoord0) * 0.2);
        if (f.a > 0.9) c = c + (1.0 - c.a) * vec4(f.rgb / f.a, 1.0);
    }
    vec2 halfSize = itemSize * 0.5;
    float d = shapeSd(qt_TexCoord0 * itemSize - halfSize, halfSize * box);
    float px = max(fwidth(d), 1e-4);
    float w = 1.2 * max(soft, 0.1);
    float m = 1.0 - smoothstep(-(w + 0.4) * px, -0.4 * px, d);
    fragColor = c * m * qt_Opacity;
}
