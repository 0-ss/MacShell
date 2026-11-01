#version 440
// Paints the window's captured image onto the genie mesh (see genie.vert). The uniform block must match the
// vertex shader's exactly.
//
// Build:  /usr/lib/qt6/bin/qsb --qt6 -o genie.frag.qsb genie.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    vec4 win;
    vec4 target;
};

layout(binding = 1) uniform sampler2D source;

void main()
{
    vec4 c = texture(source, qt_TexCoord0);
    // the last stretch into the Dock fades a little, so the tip never ends in a hard sliver
    float tail = 1.0 - smoothstep(0.82, 1.0, progress) * 0.85;
    fragColor = c * qt_Opacity * tail;
}
