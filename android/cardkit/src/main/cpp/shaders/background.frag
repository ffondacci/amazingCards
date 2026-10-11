#version 450
// Studio or night backdrop, floor glow, light rays and halo, dim and flash.
#include "common.glsl"

struct RayWedge { float start; float width; float alpha; float pad; };
layout(std140, set = 0, binding = 3) uniform Rays {
    RayWedge wedges[160];
    ivec4 counts;   // coarse count, fine count (fine wedges follow the coarse ones)
} rays;

layout(location = 0) in vec2 vUV;
layout(location = 0) out vec4 outColor;

float radialT(vec2 css, vec2 center, vec2 radii) { vec2 d = (css - center) / max(radii, vec2(1e-4)); return length(d); }

float rayLayer(float angleDeg, int first, int count, float spin) {
    float a = mod(angleDeg - spin, 360.0);
    float v = 0.0;
    for (int i = 0; i < count; ++i) {
        RayWedge w = rays.wedges[first + i];
        float t = a - w.start;
        if (t < 0.0 || t > w.width) { continue; }
        float mid = w.width * 0.5;
        v += w.alpha * (1.0 - abs(t - mid) / mid);
    }
    return v;
}

void main() {
    bool night = frame.params.z > 0.5;
    bool premium = frame.screen2.x > 0.5;
    vec2 size = frame.screen2.yz;
    vec2 css = vec2(vUV.x, 1.0 - vUV.y);
    float floorLine = frame.screen.x;
    float vmax = max(size.x, size.y), vmin = min(size.x, size.y);
    vec2 px = css * size;

    vec3 c;
    if (night) {
        float t = radialT(css, vec2(0.74, 0.12), vec2(0.9, 0.7));
        vec3 g = t < 0.44 ? mix(vec3(0.114, 0.227, 0.549), vec3(0.043, 0.075, 0.188), t / 0.44)
                          : mix(vec3(0.043, 0.075, 0.188), vec3(0.016, 0.024, 0.051), sat((t - 0.44) / 0.56));
        c = g;
        float f = radialT(css, vec2(0.5, floorLine), vec2(0.5, 0.18));
        c = mix(c, vec3(0.275, 0.431, 1.0), 0.32 * sat(1.0 - f));
    } else {
        vec2 r = vec2(vmin / size.x, vmin / size.y);
        vec3 top = vec3(0.62, 0.66, 0.74);
        vec3 mid = vec3(0.80, 0.83, 0.88);
        vec3 low = vec3(0.90, 0.92, 0.95);
        float y = css.y;
        c = y < floorLine ? mix(top, mid, smoothstep(0.0, floorLine * 0.85, y)) : mix(mid, low, smoothstep(floorLine, 1.0, y));
        float spot = radialT(css, vec2(0.5, 0.46), vec2(0.62, 0.52) * r);
        c = mix(c, vec3(0.96, 0.965, 0.975), (1.0 - smoothstep(0.0, 1.0, spot)) * 0.55);
        float f = radialT(css, vec2(0.5, floorLine + 0.02), vec2(0.75, 0.16) * r);
        float glow = f < 0.35 ? mix(1.0, 0.75, f / 0.35) : mix(0.75, 0.0, sat((f - 0.35) / 0.65));
        c = mix(c, vec3(1.0), glow * 0.9);
        float corner = radialT(css, vec2(0.5, 0.5), vec2(0.85, 0.85) * r);
        c *= 1.0 - 0.18 * smoothstep(0.55, 1.35, corner);
    }

    float raysOpacity = frame.screen.y, haloOpacity = frame.screen.z;
    if (raysOpacity > 0.001 || haloOpacity > 0.001) {
        vec3 rayColor = premium ? vec3(1.0, 0.784, 0.412) : (night ? vec3(0.588, 0.69, 1.0) : vec3(1.0, 0.855, 0.588));
        float rayA = premium ? 0.7 : (night ? 0.4 : 0.72);
        vec3 haloColor = premium ? vec3(1.0, 0.839, 0.541) : (night ? vec3(0.463, 0.573, 1.0) : vec3(1.0, 0.988, 0.957));
        float haloA = premium ? 0.9 : (night ? 0.42 : 0.95);
        vec2 centre = vec2(0.5, 0.48) * size;
        vec2 d = px - centre;
        float r = length(d);
        float m = r / (1.1 * vmax);
        float mask = m < 0.08 ? mix(1.0, 0.78, m / 0.08)
                   : m < 0.18 ? mix(0.78, 0.52, (m - 0.08) / 0.10)
                   : m < 0.28 ? mix(0.52, 0.32, (m - 0.18) / 0.10)
                   : m < 0.38 ? mix(0.32, 0.18, (m - 0.28) / 0.10)
                   : m < 0.48 ? mix(0.18, 0.09, (m - 0.38) / 0.10)
                   : m < 0.58 ? mix(0.09, 0.04, (m - 0.48) / 0.10)
                   : m < 0.70 ? mix(0.04, 0.012, (m - 0.58) / 0.12)
                   : m < 0.82 ? mix(0.012, 0.0, (m - 0.70) / 0.12) : 0.0;
        float angle = mod(atan(d.x, -d.y) * 57.29578 + 360.0, 360.0);
        float rr = rayLayer(angle, 0, rays.counts.x, frame.params.x * 9.0) * rayA
                 + rayLayer(angle, rays.counts.x, rays.counts.y, -frame.params.x * 22.5) * rayA * 0.7;
        rr = min(1.0, rr * mask) * raysOpacity;
        c = mix(c, rayColor, rr);
        float h = r / (0.85 * vmax);
        float halo = h < 0.07 ? mix(1.0, 0.86, h / 0.07)
                   : h < 0.14 ? mix(0.86, 0.64, (h - 0.07) / 0.07)
                   : h < 0.21 ? mix(0.64, 0.44, (h - 0.14) / 0.07)
                   : h < 0.28 ? mix(0.44, 0.28, (h - 0.21) / 0.07)
                   : h < 0.36 ? mix(0.28, 0.16, (h - 0.28) / 0.08)
                   : h < 0.45 ? mix(0.16, 0.085, (h - 0.36) / 0.09)
                   : h < 0.55 ? mix(0.085, 0.04, (h - 0.45) / 0.10)
                   : h < 0.66 ? mix(0.04, 0.015, (h - 0.55) / 0.11)
                   : h < 0.80 ? mix(0.015, 0.0, (h - 0.66) / 0.14) : 0.0;
        c = mix(c, haloColor, halo * haloA * haloOpacity);
    }
    float dim = frame.screen.w;
    if (dim > 0.001) {
        float t = length(px - 0.5 * size) / (0.9 * vmax);
        float k = sat((t - 0.28) / 0.72) * 0.42 * dim;
        c = mix(c, vec3(0.11, 0.063, 0.0), k);
    }
    float flash = frame.screen2.w;
    if (flash > 0.001) {
        float t = length(px - vec2(0.5, 0.45) * size) / (0.7 * vmin);
        vec3 fc = premium ? (t < 0.45 ? mix(vec3(1.0, 0.941, 0.745), vec3(1.0, 0.784, 0.353), t / 0.45) : vec3(1.0, 0.745, 0.314))
                          : (t < 0.45 ? mix(vec3(1.0), vec3(1.0, 0.98, 0.92), t / 0.45) : vec3(1.0));
        float fa = t < 0.45 ? mix(1.0, premium ? 0.6 : 0.55, t / 0.45) : mix(premium ? 0.6 : 0.55, 0.0, sat((t - 0.45) / 0.55));
        c = mix(c, fc, fa * flash);
    }
    outColor = vec4(pow(c, vec3(2.2)), 1.0);
}
