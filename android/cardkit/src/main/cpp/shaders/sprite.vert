#version 450
// A unit quad placed by the object's model matrix (shadows, aura).
#include "common.glsl"
layout(location = 0) out vec2 vUV;      // 0…1
layout(location = 1) out vec2 vCentred; // −0.5…0.5
void main() {
    const vec2 corners[6] = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
    vec2 c = corners[gl_VertexIndex];
    gl_Position = frame.viewProjection * (object.model * vec4(c, 0.0, 1.0));
    vUV = c + 0.5;
    vCentred = c;
}
