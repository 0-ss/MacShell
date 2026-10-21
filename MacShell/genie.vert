#version 440
// The macOS "genie" minimise: the window pours into its slot in the Dock like smoke into a lamp.
//
// Drawn on a fine grid (GridMesh), so every row of the window can be squeezed on its own: rows nearer the Dock
// narrow first and fall first, the top of the window follows, and the whole funnel slides into the target.
// progress 0 = the window where it is, 1 = gone into the Dock. Restoring plays the same thing backwards.
//
// Build:  /usr/lib/qt6/bin/qsb --qt6 -o genie.vert.qsb genie.vert
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    vec4 win;       // the window:       x, y, width (.z), height (.w) — item coordinates = screen coordinates
    vec4 target;    // its slot in the Dock: same layout
};

void main()
{
    vec2 uv = qt_MultiTexCoord0;
    float p = clamp(progress, 0.0, 1.0);

    // Phase 1 (first ~45%): the sides bend toward the target, most strongly near the bottom.
    // Phase 2: every row falls into the target, the bottom rows leading.
    float bend = smoothstep(0.0, 0.45, p);
    float fall = smoothstep(0.25, 1.0, p);

    // vertical: each row moves from its place in the window to its place in the target, bottom rows first
    float rowT = clamp(fall * 1.35 - (1.0 - uv.y) * 0.35, 0.0, 1.0);
    rowT = rowT * rowT * (3.0 - 2.0 * rowT);
    float y0 = win.y + uv.y * win.w;
    float y1 = target.y + uv.y * target.w;
    float y = mix(y0, y1, rowT);

    // horizontal: how squeezed this row is depends on how close it now is to the Dock
    float span = max(1.0, (target.y + target.w) - win.y);
    float k = clamp((y - win.y) / span, 0.0, 1.0);
    float squeeze = clamp(bend * smoothstep(0.0, 1.0, k) + rowT, 0.0, 1.0);
    float left = mix(win.x, target.x, squeeze);
    float right = mix(win.x + win.z, target.x + target.z, squeeze);
    float x = mix(left, right, uv.x);

    qt_TexCoord0 = uv;
    gl_Position = qt_Matrix * vec4(x, y, 0.0, 1.0);
}
