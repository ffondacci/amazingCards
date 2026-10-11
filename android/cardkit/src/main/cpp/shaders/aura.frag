#version 450
// Glow (flags.z = 0) or light rays (flags.z = 1) behind the rare card.
#include "common.glsl"
layout(location = 0) in vec2 vUV;
layout(location = 1) in vec2 vCentred;
layout(location = 0) out vec4 outColor;
void main() {
    vec2 p = vCentred * 2.0;
    float r = length(p);
    float opacity = object.flags.w;
    if (object.flags.z < 0.5) {
        vec3 c = r < 0.35 ? mix(vec3(1.0, 0.84, 0.43), vec3(1.0, 0.745, 0.275), r / 0.35) : vec3(1.0, 0.69, 0.18);
        float a = r < 0.35 ? mix(0.95, 0.5, r / 0.35) : mix(0.5, 0.0, sat((r - 0.35) / 0.65));
        outColor = vec4(c * a * opacity, a * opacity);
        return;
    }
    float angle = atan(p.y, p.x);
    float total = 0.0;
    vec3 color = vec3(0.0);
    for (int l = 0; l < 3; ++l) {
        float scale = l == 0 ? 2.4 : (l == 1 ? 1.5 : 1.0);
        float layerAlpha = l == 0 ? 0.18 : (l == 1 ? 0.32 : 0.55);
        float seed = 5.0 + float(l) * 31.0;
        for (int w = 0; w < 22; ++w) {
            float k = float(w);
            float centre = (k + hash1(seed + k * 1.7) * 0.8) * 6.2831853 / 22.0;
            float width = (0.01 + hash1(seed + k * 2.3 + 1.0) * 0.03) * scale;
            float len = 0.5 + hash1(seed + k * 3.1 + 2.0) * 0.5;
            float d = angle - centre;
            d = d - 6.2831853 * round(d / 6.2831853);
            float wedge = 1.0 - smoothstep(width * 0.6, width, abs(d));
            if (wedge <= 0.0) { continue; }
            float t = r / len;
            float a = t < 0.45 ? mix(1.0, 0.45, t / 0.45) : mix(0.45, 0.0, sat((t - 0.45) / 0.55));
            vec3 c = t < 0.45 ? mix(vec3(1.0, 0.91, 0.63), vec3(1.0, 0.81, 0.43), t / 0.45) : vec3(1.0, 0.745, 0.275);
            float contribution = wedge * a * layerAlpha;
            color += c * contribution;
            total += contribution;
        }
    }
    total = min(total, 1.0);
    outColor = vec4(color * opacity, total * opacity);
}
