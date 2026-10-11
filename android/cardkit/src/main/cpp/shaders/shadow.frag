#version 450
#include "common.glsl"
layout(location = 0) in vec2 vUV;
layout(location = 1) in vec2 vCentred;
layout(location = 0) out vec4 outColor;
void main() {
    float r = length(vUV - 0.5) * 2.0;
    float a = r < 0.45 ? mix(0.6, 0.24, r / 0.45) : mix(0.24, 0.0, sat((r - 0.45) / 0.55));
    outColor = vec4(0.0, 0.0, 0.0, a * object.flags.w);
}
