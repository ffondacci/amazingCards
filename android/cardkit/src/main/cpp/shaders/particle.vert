#version 450
// Sparks and smoke: camera-facing billboards.
#include "common.glsl"
struct SpriteInstance { vec4 position; vec4 color; vec4 extra; };
layout(std430, set = 0, binding = 5) readonly buffer Sprites { SpriteInstance items[]; } sprites;
layout(location = 0) out vec2 vUV;
layout(location = 1) out vec4 vColor;
layout(location = 2) out float vKind;
void main() {
    const vec2 corners[6] = vec2[6](vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, -0.5), vec2(0.5, 0.5), vec2(-0.5, 0.5));
    SpriteInstance inst = sprites.items[gl_InstanceIndex];
    vec2 c = corners[gl_VertexIndex];
    float a = inst.extra.x;
    vec2 r = vec2(c.x * cos(a) - c.y * sin(a), c.x * sin(a) + c.y * cos(a)) * inst.position.w;
    vec3 toCamera = normalize(frame.cameraPosition.xyz - inst.position.xyz);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), toCamera));
    vec3 up = cross(toCamera, right);
    vec3 world = inst.position.xyz + right * r.x + up * r.y;
    gl_Position = frame.viewProjection * vec4(world, 1.0);
    vUV = c + 0.5;
    vColor = inst.color;
    vKind = inst.extra.y;
}
