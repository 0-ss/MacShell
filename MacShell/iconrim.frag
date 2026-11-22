#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float power;
    float strength;
    float soft;
    vec4 radii;
};

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
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 c = itemSize * 0.5;
    vec2 rel = p - c;
    float d0 = shapeSd(rel, c);
    float px = max(fwidth(d0), 1e-4);
    float w = 1.2 * max(soft, 0.1);
    float d = d0 + (0.5 * w + 0.4) * px;
    float inside = 1.0 - smoothstep(-0.5 * w * px, 0.5 * w * px, d);

    float line = exp(-max(-d, 0.0) / 1.1) * inside;
    float sheen = exp(-max(-d, 0.0) / 7.0) * inside;

    vec2 dir = normalize(rel + vec2(0.0001));
    float key = dot(dir, normalize(vec2(-0.55, -0.83)));
    float lit = pow(max(key, 0.0), 1.4);
    float bounce = pow(max(-key, 0.0), 2.5);

    float a = line * (0.08 + 0.42 * lit + 0.18 * bounce) + sheen * (0.07 * lit + 0.02 * bounce);
    a = clamp(a * strength, 0.0, 1.0);

    fragColor = vec4(vec3(a), a) * qt_Opacity;
}
