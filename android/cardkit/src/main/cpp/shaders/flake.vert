#version 450
// Foil flakes: an irregular quad per instance, lit as metal.
#include "common.glsl"
struct FlakeInstance { mat4 model; vec4 color; };
layout(std430, set = 0, binding = 4) readonly buffer Flakes { FlakeInstance items[]; } flakes;
layout(location = 0) out vec3 vNormal;
layout(location = 1) out vec3 vWorld;
layout(location = 2) out vec4 vColor;
void main() {
    const vec2 shape[4] = vec2[4](vec2(-0.5, -0.35), vec2(0.55, -0.5), vec2(0.35, 0.45), vec2(-0.4, 0.5));
    const int order[6] = int[6](0, 1, 2, 0, 2, 3);
    vec2 c = shape[order[gl_VertexIndex]];
    FlakeInstance inst = flakes.items[gl_InstanceIndex];
    vec4 world = inst.model * vec4(c, 0.0, 1.0);
    gl_Position = frame.viewProjection * world;
    vWorld = world.xyz;
    mat3 m3 = mat3(inst.model[0].xyz, inst.model[1].xyz, inst.model[2].xyz);
    vNormal = normalize(m3 * vec3(0.0, 0.0, 1.0));
    vColor = inst.color;
}
