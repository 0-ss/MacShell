#version 440
// Feathered top and bottom edges (MacLock lyrics): content fades out smoothly instead of being cut off.
// Build:  /usr/lib/qt6/bin/qsb --qt6 -o fade.frag.qsb fade.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float fadeTop;     // fraction of the height that fades in at the top
    float fadeBottom;  // fraction of the height that fades out at the bottom
};
layout(binding = 1) uniform sampler2D source;
void main()
{
    float y = qt_TexCoord0.y;
    float a = smoothstep(0.0, fadeTop, y) * smoothstep(0.0, fadeBottom, 1.0 - y);
    fragColor = texture(source, qt_TexCoord0) * (a * qt_Opacity);
}
