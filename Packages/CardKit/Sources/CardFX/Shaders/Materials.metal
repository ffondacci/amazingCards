//
//  Materials.metal
//  CardKit · CardFX
//
//  Procedural backgrounds and materials: booster foil wrapper, star field,
//  nebula, reveal burst, loading shimmer. Generators ignore the source colour
//  and only keep its alpha so they respect the clip shape they are drawn in.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace ckm {

constant float TAU = 6.28318530718;

static inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float2x2 m = float2x2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < octaves; ++i) {
        value += amplitude * vnoise(p);
        p = m * p * 2.02 + 11.3;
        amplitude *= 0.5;
    }
    return value;
}

static inline float3 spectrum(float t) {
    return 0.5 + 0.5 * cos(TAU * (t + float3(0.0, 0.33, 0.67)));
}

static inline float stars(float2 uv, float scale, float2 pan, float time, float seed) {
    float2 g = (uv + pan) * scale;
    float2 cell = floor(g);
    float2 l = fract(g) - 0.5;
    float r = hash21(cell + seed);
    float exists = step(0.80, r);
    float2 jitter = (float2(hash21(cell + seed + 1.3), hash21(cell + seed + 9.2)) - 0.5) * 0.7;
    l -= jitter;
    float radius = mix(0.03, 0.14, hash21(cell + seed + 5.5));
    float core = smoothstep(radius, 0.0, length(l));
    float ray = smoothstep(0.02, 0.0, min(abs(l.x), abs(l.y)))
        * smoothstep(radius * 3.0, 0.0, max(abs(l.x), abs(l.y)));
    float twinkle = 0.6 + 0.4 * sin(time * 1.1 + r * TAU);
    return exists * max(core, ray * 0.8) * twinkle;
}

static inline float2 resolvePointer(float2 pointer, float2 tilt) {
    float valid = step(0.0, pointer.x) * step(0.0, pointer.y);
    float2 fallback = clamp(float2(0.5) + tilt * 0.5, 0.0, 1.0);
    return mix(fallback, clamp(pointer, 0.0, 1.0), valid);
}

static inline float3 unpremul(half4 c) {
    return c.a > 0.001h ? float3(c.rgb) / float(c.a) : float3(0.0);
}

static inline half4 premul(float3 rgb, half a) {
    return half4(half3(clamp(rgb, 0.0, 1.0)) * a, a);
}

} // namespace ckm

using namespace ckm;

/// Crinkled metallic wrapper of a booster pack, tinted around `hue`.
/// Blends over the source so the pack keeps its printed artwork.
[[stitchable]] half4 ck_foilWrap(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float hue
) {
    if (color.a < 0.004h) { return color; }
    float2 uv = position / max(size, float2(1.0));
    float2 pan = resolvePointer(pointer, tilt) - 0.5;
    float crinkle = fbm(uv * float2(7.0, 10.0), 5);
    float creases = pow(abs(sin(crinkle * 14.0 + pan.x * 4.0 + pan.y * 3.0)), 5.0);
    float facets = vnoise(uv * float2(18.0, 26.0) + pan * 2.0);
    float3 src = unpremul(color);
    float3 tint = spectrum(hue + facets * 0.25 + pan.y * 0.3);
    float3 metal = mix(src * 0.55, src * 1.35, facets) + tint * 0.10 * facets;
    metal += float3(1.0) * creases * 0.45;
    float band = pow(0.5 + 0.5 * cos((uv.x + uv.y * 0.4 - pan.x * 1.5) * TAU * 1.2), 4.0);
    metal += band * float3(0.8, 0.85, 0.95) * 0.35;
    float3 result = mix(src, metal, clamp(intensity, 0.0, 1.0));
    return premul(result, color.a);
}

/// Deep-space star field with a faint milky band. Parallax follows the tilt.
[[stitchable]] half4 ck_starfield(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float density
) {
    float2 s = max(size, float2(1.0));
    float2 uv = position / s;
    float2 q = float2(uv.x * (s.x / s.y), uv.y);
    float2 pan = tilt * 0.02;
    float3 col = float3(0.010, 0.015, 0.045);
    col += stars(q, density, pan * 0.5, time, 1.0) * float3(0.8, 0.85, 1.0) * 0.6;
    col += stars(q, density * 0.5, pan, time, 11.0) * float3(1.0, 0.95, 0.9);
    col += stars(q, density * 0.25, pan * 1.6, time, 29.0) * float3(0.9, 0.95, 1.0) * 1.2;
    float milky = fbm(q * 2.0 + float2(0.0, 0.3), 4);
    col += float3(0.08, 0.09, 0.16) * smoothstep(0.45, 0.8, milky);
    return premul(col * clamp(intensity, 0.0, 1.5), color.a);
}

/// Coloured gas clouds. `palette` selects a colour scheme (see NebulaPalette).
[[stitchable]] half4 ck_nebula(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float palette
) {
    float2 s = max(size, float2(1.0));
    float2 uv = position / s;
    float2 q = float2(uv.x * (s.x / s.y), uv.y) * 2.2 + tilt * 0.08;
    float n1 = fbm(q + time * 0.02, 5);
    float n2 = fbm(q * 1.8 + float2(7.1, 2.3) - time * 0.015, 4);
    float3 a, b, c;
    switch (int(palette + 0.5)) {
        case 1: a = float3(0.02, 0.12, 0.16); b = float3(0.05, 0.45, 0.50); c = float3(0.95, 0.70, 0.25); break;
        case 2: a = float3(0.12, 0.02, 0.04); b = float3(0.55, 0.10, 0.08); c = float3(1.00, 0.55, 0.15); break;
        case 3: a = float3(0.02, 0.10, 0.08); b = float3(0.05, 0.40, 0.30); c = float3(0.35, 0.95, 0.85); break;
        default: a = float3(0.06, 0.02, 0.18); b = float3(0.10, 0.20, 0.55); c = float3(0.85, 0.30, 0.65); break;
    }
    float3 gas = mix(a, b, n1);
    gas = mix(gas, c, smoothstep(0.50, 0.85, n2));
    gas *= 0.35 + 0.9 * smoothstep(0.3, 0.9, n1);
    gas += stars(q, 28.0, tilt * 0.01, time, 3.0) * float3(0.9, 0.95, 1.0) * 0.8;
    return premul(gas * clamp(intensity, 0.0, 1.5), color.a);
}

/// Rotating ray burst used behind a revealed rare card. Transparent outside.
[[stitchable]] half4 ck_burst(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float3 tint
) {
    float2 s = max(size, float2(1.0));
    float2 uv = position / s - 0.5;
    uv.x *= s.x / s.y;
    float r = length(uv);
    float ang = atan2(uv.y, uv.x);
    float rays = pow(0.5 + 0.5 * sin(ang * 12.0 + time * 0.8), 3.0) * 0.7
        + pow(0.5 + 0.5 * sin(-ang * 7.0 + time * 0.5 + 1.0), 4.0) * 0.5;
    float falloff = smoothstep(0.9, 0.0, r);
    float glow = smoothstep(0.35, 0.0, r) * 0.8;
    float alpha = clamp((rays * falloff + glow) * intensity, 0.0, 1.0) * float(color.a);
    float3 col = mix(tint, float3(1.0), glow * 0.6);
    return half4(half3(col * alpha), half(alpha));
}

/// Loading shimmer: a soft band travelling at a fixed pace.
[[stitchable]] half4 ck_shimmer(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float angle
) {
    if (color.a < 0.004h) { return color; }
    float2 uv = position / max(size, float2(1.0));
    float a = angle * M_PI_F / 180.0;
    float2 dir = float2(cos(a), sin(a));
    float t = dot(uv - 0.5, dir) + 0.5;
    float center = fract(time * 0.5) * 1.6 - 0.3;
    float band = 1.0 - smoothstep(0.0, 0.25, abs(t - center));
    float3 src = unpremul(color);
    float3 result = src + float3(band * intensity * 0.6);
    return premul(result, color.a);
}

/// Sparks at a cutting point: a hot core at `origin`, an ember trail fading
/// behind it (opposite to `direction`), and particles thrown backwards and
/// sideways that fall and die. Generator: ignores the source colour.
[[stitchable]] half4 ck_sparks(
    float2 position, half4 color,
    float2 size, float2 origin, float2 direction, float time, float intensity, float3 tint, float life
) {
    float2 p = position - origin;
    float2 dir = length(direction) > 0.001 ? normalize(direction) : float2(1.0, 0.0);
    float2 perp = float2(-dir.y, dir.x);
    float glow = 0.0;

    // Hot core with a flickering halo.
    float d2 = dot(p, p);
    float pulse = 0.85 + 0.15 * sin(time * 37.0) + 0.1 * sin(time * 59.0);
    glow += exp(-d2 / 110.0) * 1.6 * pulse;
    glow += exp(-d2 / 1600.0) * 0.35;

    // Ember trail along the cut, behind the front, flickering.
    float along = dot(p, -dir);
    float across = dot(p, perp);
    float flicker = 0.7 + 0.3 * vnoise(float2(along * 0.15 - time * 6.0, 3.0));
    float trail = exp(-across * across / 10.0) * smoothstep(90.0, 0.0, along) * step(0.0, along);
    glow += trail * flicker * 0.9;

    // Particles: thrown backwards and sideways, stretched along their motion.
    float lifetime = max(life, 0.1);
    for (int i = 0; i < 36; ++i) {
        float seed = float(i) * 7.31;
        float t = fract(time / lifetime + hash21(float2(seed, 1.0)));
        float age = t * lifetime;
        float back = -60.0 - 160.0 * hash21(float2(seed, 2.0));
        float side = (hash21(float2(seed, 3.0)) - 0.5) * 300.0;
        float2 velocity = dir * back + perp * side;
        float2 pos = velocity * age + float2(0.0, 160.0 * age * age);
        float2 q = p - pos;
        float2 v = velocity + float2(0.0, 320.0 * age);
        float speed = max(length(v), 1.0);
        float2 vd = v / speed;
        float alongV = dot(q, vd);
        float acrossV = dot(q, float2(-vd.y, vd.x));
        float r = 1.3 + 1.8 * hash21(float2(seed, 4.0));
        float stretch = 1.0 + speed * 0.012;
        float spark = exp(-(alongV * alongV / (2.0 * r * r * stretch * stretch) + acrossV * acrossV / (2.0 * r * r)))
            * (1.0 - t) * (0.75 + 0.25 * sin(time * 40.0 + seed));
        glow += spark * 1.7;
    }

    float a = clamp(glow * intensity, 0.0, 1.0);
    float3 col = tint * glow + float3(1.0, 0.96, 0.85) * glow * glow * 0.5;
    col = clamp(col * intensity, 0.0, 1.0);
    return half4(half3(col * a), half(a));
}
