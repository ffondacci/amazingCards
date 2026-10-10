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
    // Nothing reaches farther than this: skip the particle loop early.
    if (dot(p, p) > 280.0 * 280.0) { return half4(0.0h); }
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
    for (int i = 0; i < 20; ++i) {
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
        float r = 1.5 + 2.2 * hash21(float2(seed, 4.0));
        float stretch = 1.0 + speed * 0.012;
        float spark = exp(-(alongV * alongV / (2.0 * r * r * stretch * stretch) + acrossV * acrossV / (2.0 * r * r)))
            * (1.0 - t) * (0.75 + 0.25 * sin(time * 40.0 + seed));
        glow += spark * 1.7;
    }

    // Paper flecks: slow, fluttering, falling gently, living longer than sparks.
    float paper = 0.0;
    for (int i = 0; i < 8; ++i) {
        float seed = 200.0 + float(i) * 5.17;
        float span = lifetime * 2.2;
        float t = fract(time / span + hash21(float2(seed, 1.0)));
        float age = t * span;
        float2 velocity = dir * (-20.0 - 50.0 * hash21(float2(seed, 2.0))) + perp * (hash21(float2(seed, 3.0)) - 0.5) * 90.0;
        float2 pos = velocity * age + float2(0.0, 70.0 * age * age);
        float2 q = p - pos;
        q.x += sin(time * 9.0 + seed) * 2.0;
        paper += exp(-dot(q, q) / 3.2) * (1.0 - t);
    }

    float a = clamp((glow + paper * 0.9) * intensity, 0.0, 1.0);
    float3 col = tint * glow + float3(1.0, 0.96, 0.85) * glow * glow * 0.5 + float3(0.95, 0.93, 0.88) * paper * 0.9;
    col = clamp(col * intensity, 0.0, 1.0);
    return half4(half3(col * a), half(a));
}

// MARK: - Paper
//
// Facet model adapted from Paper Design's paper-texture shader
// (https://github.com/paper-design/shaders, Apache-2.0): the surface is a
// field of flat facets, each with its own constant slope, blended across
// rounded shoulders at the creases; a grazing light darkens every facet
// that turns away from it. Large crumples come from a handful of seed
// points, wrinkles from three octaves of a sparse cellular grid.

namespace ckpaper {

constant float TAU = 6.28318530718;
constant int CRUMPLES = 10;

static inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
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

static inline float lst(float e0, float e1, float x) {
    return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
}

static inline float2 cellTilt(float idx, float radius, float seed) {
    float2 r = hash22(float2(idx + 31.0, idx * seed + 17.0));
    float an = r.x * TAU;
    return float2(cos(an), sin(an)) * mix(0.3, 1.7, r.y * r.y) * mix(0.7, 1.0, radius);
}

/// Large facets from `CRUMPLES` seed points. Returns the slope (xy), a
/// depth term (z) and how close the pixel is to a crease (w).
static inline float4 crumples(float2 uv, float seed, float2 L, thread float &crease) {
    float near = 6e4, nearB = 6e4;
    float idx = 0.0, rad = 0.0;
    float2 nearP = float2(0.0), nearPb = float2(0.0);
    float4 seeds[CRUMPLES];
    for (int i = 0; i < CRUMPLES; ++i) {
        float2 rand = hash22(float2(float(i), float(i) * seed));
        float an = rand.x * TAU;
        float2 p = float2(cos(an), sin(an)) * rand.y;
        seeds[i] = float4(p, rand);
        float2 d = uv - p;
        float dsq = dot(d, d);
        if (dsq < near) {
            nearB = near; nearPb = nearP;
            near = dsq; idx = float(i); rad = rand.y; nearP = p;
        } else if (dsq < nearB) {
            nearB = dsq; nearPb = p;
        }
    }
    float l = sqrt(near), lb = sqrt(nearB);
    float2 dir = (uv - nearP) / max(l, 1e-4);
    float edge = lst(0.0, 0.5, lb - l);
    float shoulderLimit = l + 0.5;
    float2 tilt = cellTilt(idx, rad, seed);
    float tiltSum = 1.0;
    float2 wide = float2(0.0);
    float wideSum = 0.0;
    float toEdge = 9.0, edgeSoft = 0.0;
    for (int i = 0; i < CRUMPLES; ++i) {
        if (float(i) == idx) continue;
        float4 sd = seeds[i];
        float2 p = sd.xy;
        float2 rand = sd.zw;
        float2 d = uv - p;
        float dsq = dot(d, d);
        if (dsq < shoulderLimit * shoulderLimit) {
            float di = sqrt(dsq);
            float sh = lst(0.5, 0.0, di - l);
            wide += sh * (d / max(di, 1e-4) - dir);
            wideSum += sh;
        }
        float pairSoft = 0.01 + 0.05 * step(0.2, rand.x) + 0.3 * rand.y;
        float toBis = (dsq - near) / (0.2 * max(length(p - nearP), 1e-4));
        if (toBis < toEdge) { toEdge = toBis; edgeSoft = pairSoft; }
        float w = 1.0 - toBis / pairSoft;
        if (w > 0.0) {
            w *= w;
            tilt += w * cellTilt(float(i), rand.y, seed);
            tiltSum += w;
        }
    }
    float blend = clamp(toEdge / max(edgeSoft, 1e-4), 0.0, 1.0);
    float2 sharp = (1.0 - edge) * ((uv - nearPb) / max(lb, 1e-4) - dir);
    float2 rounding = mix(sharp, wide / max(wideSum, 1.0), min(2.0 * edgeSoft, 1.0));
    float radial = l / max(l + toEdge, 1e-4);
    // A thin mark along sharp creases, mostly where the ridge faces the
    // light; soft (rounded) creases leave none.
    float facing = 0.25 + 0.75 * max(0.0, dot(normalize(nearP - nearPb), L));
    crease = (1.0 - smoothstep(0.0, 0.12, toEdge)) * (1.0 - smoothstep(0.06, 0.22, edgeSoft)) * facing;
    return float4(tilt / tiltSum + rounding * blend * radial, 0.2 * l, edge);
}

/// One octave of small facets on a sparse cellular grid (a fifth of the
/// cells are dropped so the pattern does not read as a tiling).
static inline float2 crumpleDetail(float2 uv, float freq, float shift, float seed, float basePixel, float lineWidth, float2 L, thread float &depth, thread float &crease) {
    depth = 0.0;
    crease = 0.0;
    float2 v = uv * freq;
    float pixel = 0.9 * freq * basePixel;
    float2 base = floor(v);
    float n1 = 9.0, n2 = 9.0;
    float2 s1 = float2(0.0), s2 = float2(0.0), q1 = float2(0.0), q2 = float2(0.0);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 cell = base + float2(float(x), float(y));
            float2 q = hash22(float2(cell.y * 1.9 + 3.1 + shift, cell.x * 1.3 + 0.11 * seed));
            if (q.y > 0.8) continue;
            float2 r = hash22(float2(cell.x + 0.37 * seed + shift + 11.1, cell.y - 0.21 * seed + 5.7));
            float2 sp = cell + 0.06 + 0.88 * r;
            float2 d = v - sp;
            float dsq = dot(d, d);
            if (dsq < n1) { n2 = n1; s2 = s1; q2 = q1; n1 = dsq; s1 = sp; q1 = q; }
            else if (dsq < n2) { n2 = dsq; s2 = sp; q2 = q; }
        }
    }
    if (n1 > 8.0) return float2(0.0);
    float an1 = q1.x * TAU, mag1 = q1.y / 0.8;
    float2 t1 = float2(cos(an1), sin(an1)) * mix(0.3, 1.7, mag1 * mag1);
    float an2 = q2.x * TAU, mag2 = q2.y / 0.8;
    float2 t2 = float2(cos(an2), sin(an2)) * mix(0.3, 1.7, mag2 * mag2);
    float spanLen = max(length(s1 - s2), 1e-4);
    float toEdge = (n2 - n1) / (2.0 * spanLen);
    float pair = hash21(s1 + s2 + 1.7 * abs(s1 - s2));
    float pairSoft = 0.05 + 0.1 * step(pair, 0.4);
    float b = clamp(toEdge / max(1.5 * pixel, 0.5 * pairSoft), 0.0, 1.0);
    b = b * b * (3.0 - 2.0 * b);
    // Marks only along the sharp creases, about half of them, where the
    // ridge faces the light.
    float keep = step(0.45, hash21(s1 * 3.1 + s2 * 1.7)) * step(pairSoft, 0.1);
    float facing = max(0.0, dot(normalize(s1 - s2), L));
    crease = (1.0 - smoothstep(0.0, lineWidth, toEdge)) * keep * (0.3 + 0.7 * facing);
    float d1 = max(sqrt(n1), 1e-4);
    depth = 0.2 * d1;
    float shoulderAmt = max(0.0, 1.0 - toEdge / 0.42) * b;
    float2 shoulder = float2(0.0);
    if (shoulderAmt > 0.0) {
        float d2 = max(sqrt(n2), 1e-4);
        shoulder = shoulderAmt * ((v - s2) / d2 - (v - s1) / d1);
    }
    float2 mid = 0.5 * (t1 + t2);
    return mid + (t1 - mid) * b + 0.9 * shoulder;
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

} // namespace ckpaper

/// Crumpled paper wrapper: large and small facets lit by a grazing light
/// that follows the tilt / pointer, the print bending with the relief,
/// crimp bumps in the sealed bands, the pillow of the cards inside, and a
/// fine grain plus fibres. `intensity` fades the whole treatment.
[[stitchable]] half4 ck_paper(
    float2 position, SwiftUI::Layer layer,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float bulge, float crimp
) {
    float2 s = max(size, float2(1.0));
    float2 uv01 = position / s;
    float aspect = s.x / s.y;
    float2 patternUV = (uv01 - 0.5) * float2(aspect, 1.0);
    float basePixel = 1.0 / s.y;
    const float seed = 7.0;

    float2 pnt = ckpaper::resolvePointer(pointer, tilt) - 0.5;
    float2 L = normalize(float2(-0.35 + pnt.x * 1.4, -0.75 + pnt.y * 1.4));

    float2 warp = float2(ckpaper::vnoise(patternUV * 3.0 + 2.0), ckpaper::vnoise(patternUV * 3.0 + 9.0)) - 0.5;
    float2 crumplesUV = patternUV * 2.2 + 0.03 * warp;

    // Large crumples. Only these bend the print: fine wrinkles would mangle text.
    float creaseBig = 0.0;
    float4 c = ckpaper::crumples(crumplesUV, seed, L, creaseBig);
    float2 bend = 0.5 * c.xy;
    float2 relief = bend;
    relief -= 0.1 * max(dot(relief, L), 0.0) * L;

    // Wrinkles, two octaves of smaller facets.
    float detailFreq = 5.0;
    float detailAmp = 0.22;
    float2 detailGrad = float2(0.0);
    float crease = creaseBig;
    float creaseWeight = 0.6;
    for (int i = 0; i < 2; ++i) {
        float layerDepth, layerCrease;
        detailGrad += detailAmp * ckpaper::crumpleDetail(
            crumplesUV, detailFreq, 31.0 * float(i), seed, basePixel * 2.2, 0.045, L, layerDepth, layerCrease
        );
        crease = max(crease, layerCrease * creaseWeight);
        creaseWeight *= 0.6;
        detailAmp *= 0.45;
        detailFreq *= 2.1;
    }
    float2 detailTilt = 1.5 * detailGrad;
    detailTilt -= 0.65 * max(dot(detailTilt, L), 0.0) * L;
    relief += detailTilt;

    // Crimp bumps in the sealed bands, pillow of the cards inside.
    float band = step(position.y, crimp) + step(s.y - crimp, position.y);
    float tri = sign(fract(position.x / (s.x / 28.0)) - 0.5);
    relief.x += 0.6 * tri * band;
    float2 cuv = uv01 * 2.0 - 1.0;
    float2 pillow = float2(
        -sign(cuv.x) * pow(abs(cuv.x), 1.6) * (1.0 - pow(abs(cuv.y), 2.6)),
        -sign(cuv.y) * pow(abs(cuv.y), 1.6) * (1.0 - pow(abs(cuv.x), 2.6))
    );
    relief += bulge * 0.9 * pillow;

    // The print bends gently with the large facets (capped at a few points).
    float2 offset = (bend * 2.2 + bulge * 0.6 * pillow) * intensity;
    float offsetLength = length(offset);
    if (offsetLength > 2.5) { offset *= 2.5 / offsetLength; }
    float2 displaced = clamp(position - offset, float2(0.0), s);
    half4 src = layer.sample(displaced);
    if (src.a < 0.004h) { return src; }

    // Grazing light: facets turning away go dark, facets facing it glow a little.
    const float grazing = 0.7;
    float unlit = cos(grazing);
    float slope = clamp(dot(relief, L), -1.2, 1.2);
    float lit = max(cos(slope + grazing), 0.0);
    float lightPower = mix(0.6, 1.0, clamp(0.5 + dot(uv01 - 0.5, L), 0.0, 1.0));
    float shade = (lit - unlit) * 1.3 * lightPower;

    // Paper grain and fibres.
    float grain = (ckpaper::vnoise(position * 0.9) - 0.5) * 0.10 + (ckpaper::hash21(floor(position * 0.5)) - 0.5) * 0.05;
    float fibre = pow(1.0 - abs(2.0 * ckpaper::vnoise(float2(position.x * 0.12, position.y * 0.45) + 3.0) - 1.0), 8.0) * 0.06;

    float3 rgb = ckpaper::unpremul(src);
    float3 paper = rgb * (1.0 + shade + grain + fibre);
    // Glossy wrapper: each facet returns its own sheen, flat areas none.
    float sheen = (pow(lit, 6.0) - pow(unlit, 6.0)) * 0.45 * lightPower;
    paper += sheen * float3(1.0, 0.98, 0.95);
    // Fold marks: the print whitens where the paper broke along a crease,
    // brighter on the side that faces the light.
    float3 mark = float3(0.95, 0.93, 0.89) * (0.75 + 0.45 * lit);
    paper = mix(paper, mark, crease * 0.42);
    float3 result = mix(rgb, paper, clamp(intensity, 0.0, 1.0));
    return ckpaper::premul(result, src.a);
}

/// Local paper tension drawn over a wrapper: a dent and radial wrinkles under
/// the finger, ripples ahead of the cut. Generator: emits light and shade
/// with alpha, composite it normally over the pack.
[[stitchable]] half4 ck_paperTension(
    float2 position, half4 color,
    float2 size, float2 point, float front, float direction, float strength, float time
) {
    if (strength < 0.005) { return half4(0.0h); }
    const float e = 1.0;
    float h[4];
    const float2 offsets[4] = { float2(e, 0.0), float2(-e, 0.0), float2(0.0, e), float2(0.0, -e) };
    for (int k = 0; k < 4; ++k) {
        float2 q = position + offsets[k];
        float2 d = q - point;
        float r = length(d);
        float v = -strength * 9.0 * exp(-r * r / (2.0 * 20.0 * 20.0));
        float ang = atan2(d.y, d.x);
        v -= strength * 2.2 * exp(-r / 55.0) * pow(0.5 + 0.5 * sin(ang * 9.0 + 1.3), 5.0) * smoothstep(0.0, 12.0, r);
        float ahead = (q.x - front) * direction;
        float ripple = sin(ahead * 0.45 - time * 2.0) * exp(-max(ahead, 0.0) / 45.0) * step(0.0, ahead);
        float band = exp(-pow((q.y - point.y) / 26.0, 2.0));
        v -= strength * 2.4 * ripple * band;
        h[k] = v;
    }
    float3 n = normalize(float3(-(h[0] - h[1]) / (2.0 * e) * 1.4, -(h[2] - h[3]) / (2.0 * e) * 1.4, 1.0));
    float3 L = normalize(float3(-0.35, -0.55, 0.9));
    float flat = L.z;
    float diffuse = max(dot(n, L), 0.0);
    float3 R = reflect(-L, n);
    float spec = pow(max(R.z, 0.0), 32.0);
    float delta = (diffuse - flat) * 0.9 + spec * 0.5;
    float a = clamp(abs(delta), 0.0, 0.8);
    float3 col = delta > 0.0 ? float3(1.0, 0.98, 0.9) : float3(0.0);
    return half4(half3(col * a), half(a));
}
