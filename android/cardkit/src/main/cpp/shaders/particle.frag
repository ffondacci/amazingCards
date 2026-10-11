#version 450
#include "common.glsl"
layout(location = 0) in vec2 vUV;
layout(location = 1) in vec4 vColor;
layout(location = 2) in float vKind;
layout(location = 0) out vec4 outColor;
void main() {
    float r = length(vUV - 0.5) * 2.0;
    float a;
    if (vKind < 0.5) { a = r < 0.3 ? mix(1.0, 0.7, r / 0.3) : mix(0.7, 0.0, sat((r - 0.3) / 0.7)); }
    else { a = r < 0.45 ? mix(0.6, 0.22, r / 0.45) : mix(0.22, 0.0, sat((r - 0.45) / 0.55)); }
    a *= vColor.a;
    if (a < 0.002) { discard; }
    outColor = vec4(vColor.rgb * a, a);
}
