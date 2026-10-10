//
//  Holo.metal
//  CardKit · CardFX
//
//  Procedural foil treatments for collectible cards: every style is synthesized
//  on the GPU from noise, gradients and the pointer / tilt of the card. No
//  texture assets. Look inspired by physical trading-card foils and by the
//  open-source references listed in the project README (ShaderKit, MIT;
//  pokemon-cards-css, GPL — not copied).
//
//  Argument convention (shared with Swift, order matters):
//    float2 size, float2 tilt (-1…1), float2 pointer (0…1, negative = none),
//    float time, float intensity, then effect specific parameters.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace ck {

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

static inline float3 pastel(float t) {
    return mix(float3(0.76), spectrum(t), 0.55);
}

static inline float luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }
static inline float3 screen(float3 b, float3 s) { return 1.0 - (1.0 - b) * (1.0 - s); }
static inline float3 overlay(float3 b, float3 s) {
    float3 lo = 2.0 * b * s;
    float3 hi = 1.0 - 2.0 * (1.0 - b) * (1.0 - s);
    return mix(lo, hi, step(float3(0.5), b));
}
static inline float3 exclusion(float3 b, float3 s) { return b + s - 2.0 * b * s; }

static inline float glarePoint(float2 uv, float2 p, float radius, float power) {
    float d = length((uv - p) * float2(1.0, 1.12));
    return pow(smoothstep(radius, 0.0, d), power);
}

static inline float sparkleLayer(float2 uv, float scale, float2 pointer, float time, float seed) {
    float2 g = uv * scale;
    float2 cell = floor(g);
    float2 l = fract(g) - 0.5;
    float r = hash21(cell + seed);
    float2 jitter = (float2(hash21(cell + seed + 3.1), hash21(cell + seed + 7.7)) - 0.5) * 0.6;
    l -= jitter;
    float phase = r * TAU + time * (0.8 + r * 1.4) + dot(pointer, float2(5.3, -4.1));
    float visibility = pow(max(0.0, sin(phase)), 10.0);
    float core = smoothstep(0.10 + r * 0.05, 0.0, length(l));
    float cross = smoothstep(0.02, 0.0, min(abs(l.x), abs(l.y)))
        * smoothstep(0.28, 0.02, max(abs(l.x), abs(l.y)));
    return max(core, cross * 0.7) * visibility;
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

static inline float etched(float x, float width) {
    float c = abs(fract(x) - 0.5);
    return 1.0 - smoothstep(width, width + 0.1, c);
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

// Blends that keep dark ink readable: the foil shows more on light pixels.
static inline float3 applyScreen(float3 src, float3 foil, float amount) {
    float readability = 0.25 + luma(src) * 0.75;
    return mix(src, screen(src, clamp(foil, 0.0, 1.0)), clamp(amount * readability, 0.0, 1.0));
}
static inline float3 applyOverlay(float3 src, float3 foil, float amount) {
    float readability = 0.30 + luma(src) * 0.70;
    return mix(src, overlay(src, clamp(foil, 0.0, 1.0)), clamp(amount * readability, 0.0, 1.0));
}
static inline float3 applyExclusion(float3 src, float3 foil, float amount) {
    float readability = 0.25 + luma(src) * 0.75;
    return mix(src, exclusion(src, clamp(foil, 0.0, 1.0)), clamp(amount * readability, 0.0, 1.0));
}

// MARK: - Foil styles

// 0 · Regular holo: diagonal rainbow bands sliding with the pointer, fine
// vertical scan lines, two soft travelling bars and a glare.
static inline float3 regularHolo(float2 uv, float2 p, float2 pan, float dist) {
    float phase = dot(uv - pan * float2(1.6, 2.2), normalize(float2(0.42, 0.91))) * 3.0;
    float3 rainbow = spectrum(phase);
    float lines = mix(0.35, 1.0, step(0.5, fract(uv.x * 110.0)));
    float barA = pow(0.5 + 0.5 * sin((uv.x + pan.x * 1.2 + pan.y * 0.4) * TAU * 3.0), 6.0);
    float barB = pow(0.5 + 0.5 * sin((uv.x - pan.x * 0.9 - pan.y * 0.6) * TAU * 4.6 + 1.1), 9.0);
    float g = glarePoint(uv, p, 0.85, 1.7);
    float3 foil = rainbow * (0.20 + lines * 0.45);
    foil += float3(0.75, 0.80, 0.86) * (barA * 0.30 + barB * 0.20);
    foil += g * float3(0.40, 0.44, 0.48);
    return foil * (0.75 + dist * 0.30);
}

// 1 · Cosmos: three star layers with different parallax over a soft nebula.
static inline float3 cosmosHolo(float2 uv, float2 p, float2 pan, float time) {
    float a = stars(uv, 12.0, pan * 0.15, time, 2.0);
    float b = stars(uv, 24.0, pan * -0.22, time, 23.0);
    float c = stars(uv, 44.0, pan * 0.32, time, 61.0);
    float phase = dot(uv + pan * 0.7, normalize(float2(0.2, 0.98))) * 2.5;
    float nebula = fbm(uv * 4.0 + pan * 0.6, 4);
    float g = glarePoint(uv, p, 0.95, 1.3);
    float3 foil = spectrum(phase) * (0.10 + nebula * 0.24);
    foil += pastel(phase + 0.2) * g * 0.30;
    foil += float3(0.85, 0.92, 1.0) * a;
    foil += float3(0.70, 0.85, 1.0) * b * 0.7;
    foil += float3(1.0, 0.85, 0.95) * c * 0.5;
    return foil;
}

// 2 · Reverse holo: textured silver foil with rings around the pointer and a
// fine diamond pattern. Meant for the frame, not the artwork.
static inline float3 reverseHolo(float2 uv, float2 p, float2 pan) {
    float rings = 0.5 + 0.5 * cos(length(uv - p) * TAU * 2.0);
    float diag = 0.5 + 0.5 * sin(dot(uv + pan * 1.1, normalize(float2(1.0, -1.0))) * TAU * 2.4);
    float2 g = (uv + pan * 0.1) * float2(26.0, 38.0);
    float2 l = fract(g) - 0.5;
    float diamond = 1.0 - smoothstep(0.30, 0.46, abs(l.x) + abs(l.y));
    float tex = fbm(uv * 9.0 + pan * 1.3, 3);
    float foil = abs(rings - diag) * (0.55 + tex * 0.45) + diamond * 0.18;
    return mix(float3(0.10, 0.12, 0.17), float3(0.90, 0.95, 1.0), clamp(foil, 0.0, 1.0));
}

// 3 · Galaxy: coloured gas clouds drifting slowly, with stars.
static inline float3 galaxyHolo(float2 uv, float2 p, float2 pan, float time) {
    float2 q = uv * 2.6 + pan * 0.5;
    float n1 = fbm(q + float2(time * 0.03, 0.0), 5);
    float n2 = fbm(q * 1.7 + float2(5.2, -3.1) - time * 0.02, 4);
    float3 gas = mix(float3(0.08, 0.02, 0.25), float3(0.05, 0.25, 0.55), n1);
    gas = mix(gas, float3(0.55, 0.10, 0.45), smoothstep(0.45, 0.8, n2));
    gas += spectrum(n1 * 1.5 + pan.x) * 0.15 * smoothstep(0.5, 0.75, n1);
    float s = stars(uv, 30.0, pan * 0.2, time, 7.0) + stars(uv, 60.0, pan * -0.1, time, 41.0) * 0.6;
    float g = glarePoint(uv, p, 0.9, 1.4);
    return gas * (0.8 + g * 0.6) + s * float3(0.9, 0.95, 1.0);
}

// 4 · Rainbow rare: two crossing rainbow gradients, glitter, etched stripes.
static inline float3 rainbowHolo(float2 uv, float2 p, float2 pan, float time) {
    float phaseA = dot(uv + pan * 1.1, normalize(float2(0.7, -0.7))) * 2.2;
    float phaseB = dot(uv - pan * 1.3, normalize(float2(0.5, -0.87))) * 2.7 + 0.3;
    float stripe = etched(dot(uv + pan, normalize(float2(-0.7, 0.72))) * 20.0, 0.35);
    float3 foil = mix(spectrum(phaseA), spectrum(phaseB), 0.4 + stripe * 0.3);
    float tex = 0.5 + 0.5 * sin(length(uv - 0.5 + pan * 0.15) * 70.0);
    foil *= 0.35 + tex * 0.25 + stripe * 0.2;
    float sp = sparkleLayer(uv, 34.0, p, time, 11.0) * 0.6 + sparkleLayer(uv + 0.017, 52.0, p, time, 71.0) * 0.4;
    foil += sp;
    foil += pastel(phaseB + 0.2) * glarePoint(uv, p, 0.9, 1.4) * 0.25;
    return foil;
}

static inline float geometricFoil(float2 uv, float2 pan) {
    float2 q = (uv + pan * 0.12) * float2(12.0, 17.0);
    float2 cell = floor(q);
    float2 l = fract(q) - 0.5;
    float dA = 1.0 - smoothstep(0.03, 0.09, abs(l.x + l.y));
    float dB = 1.0 - smoothstep(0.03, 0.09, abs(l.x - l.y));
    float diamond = 1.0 - smoothstep(0.34, 0.48, abs(l.x) + abs(l.y));
    float alt = step(0.5, hash21(cell));
    return mix(max(dA, dB), diamond, alt) * 0.8;
}

// 5 · Gold: geometric gold foil with a conic highlight and sparkles.
static inline float3 goldHolo(float2 uv, float2 p, float2 pan, float time) {
    float geo = geometricFoil(uv, pan);
    float ang = atan2(uv.y - 0.5 - pan.y * 0.2, uv.x - 0.5 - pan.x * 0.2);
    float conic = 0.5 + 0.5 * sin(ang * 4.0 + length(uv - p) * 6.0);
    float g = glarePoint(uv, p, 0.9, 1.4);
    float3 dark = float3(0.36, 0.23, 0.05);
    float3 bright = float3(1.0, 0.80, 0.25);
    float3 foil = mix(dark, bright, clamp(geo * 0.55 + conic * 0.25 + g * 0.25, 0.0, 1.0));
    foil += float3(1.0, 0.9, 0.5) * (sparkleLayer(uv, 30.0, p, time, 5.0) * 0.7 + sparkleLayer(uv + 0.02, 50.0, p, time, 29.0) * 0.4);
    return foil;
}

// 6 · Amazing rare: saturated paint splashes with glitter.
static inline float3 amazingHolo(float2 uv, float2 p, float2 pan, float time) {
    float splash = smoothstep(0.45, 0.72, fbm(uv * 5.0 + float2(3.0, 8.0), 4));
    float phase = dot(uv - pan * 2.0, normalize(float2(-0.65, 0.76))) * 2.5;
    float3 foil = spectrum(phase) * (0.12 + splash * 0.5) + pastel(phase + 0.35) * splash * 0.25;
    foil += float3(0.7, 0.82, 0.8) * glarePoint(uv, p, 1.0, 1.1) * 0.2;
    foil += float3(1.0, 0.96, 0.9) * (sparkleLayer(uv, 28.0, p, time, 8.0) * 0.7 + sparkleLayer(uv + 0.013, 44.0, p, time, 42.0) * 0.45);
    return foil;
}

// 7 · Radiant: etched diagonal lattice, rainbow, sparkles.
static inline float3 radiantHolo(float2 uv, float2 p, float2 pan, float time) {
    float la = etched(dot(uv + pan * 0.5, normalize(float2(1.0, 1.0))) * 70.0, 0.36);
    float lb = etched(dot(uv + pan * 0.5, normalize(float2(-1.0, 1.0))) * 70.0, 0.36);
    float lattice = max(la, lb);
    float phase = dot(uv - pan * 1.5, normalize(float2(0.8, 0.6))) * 2.2;
    float3 foil = spectrum(phase) * (0.15 + lattice * 0.55);
    foil += float3(0.7, 0.75, 0.8) * glarePoint(uv, p * 0.5 + 0.25, 0.95, 1.5) * 0.25;
    foil += sparkleLayer(uv, 32.0, p, time, 13.0) * 0.8;
    return foil;
}

// 8 · Prism: diffraction-grating rings around the pointer, CD like.
static inline float3 prismHolo(float2 uv, float2 p, float2 pan) {
    float2 d = uv - p;
    d.y *= 1.4;
    float r = length(d);
    float ang = atan2(d.y, d.x);
    float ring = r * 9.0 - ang / TAU * 2.0 + pan.x * 2.0;
    float3 foil = spectrum(ring);
    float grating = 0.5 + 0.5 * sin(uv.x * 220.0 + ang * 3.0);
    foil *= 0.35 + grating * 0.35;
    foil *= smoothstep(1.3, 0.05, r) * 0.9 + 0.1;
    foil += glarePoint(uv, p, 0.5, 2.0) * 0.6;
    return foil;
}

// 9 · Pearl: thin-film iridescence driven by the source luminance and tilt.
static inline float3 pearlHolo(float2 uv, float2 p, float2 pan, float lum) {
    float film = lum * 1.6 + dot(pan, uv - 0.5) * 2.5 + fbm(uv * 3.0 + pan, 3) * 0.6;
    float3 iridescence = pastel(film);
    float g = glarePoint(uv, p, 1.1, 1.0);
    return mix(float3(0.85, 0.88, 0.92), iridescence, 0.7) * (0.55 + g * 0.5);
}

// 10 · Brushed metal: anisotropic streaks and a travelling specular band.
static inline float3 brushedHolo(float2 uv, float2 p, float2 pan) {
    float streak = vnoise(float2(uv.x * 6.0 + pan.x, uv.y * 420.0)) * 0.6
        + vnoise(float2(uv.x * 3.0, uv.y * 900.0 + 7.0)) * 0.4;
    float band = pow(0.5 + 0.5 * cos((uv.y - p.y) * TAU * 0.9), 3.0);
    float g = glarePoint(uv, p, 1.0, 1.2);
    float3 base = float3(0.62, 0.66, 0.72) * (0.6 + streak * 0.5);
    base += float3(1.0) * band * 0.35 + g * 0.3;
    base += spectrum(uv.y * 0.5 + pan.y) * 0.06;
    return base;
}

// 11 · Full art (sun pillar): vertical rainbow, diamond-plate etching, grain.
static inline float3 sunpillarHolo(float2 uv, float2 p, float2 pan, float dist) {
    float phase = uv.y * 1.3 - pan.y * 1.6 + pan.x * 0.3;
    float3 rainbow = spectrum(phase);
    float grain = vnoise(float2(uv.x * 240.0, uv.y * 380.0));
    float ridgeA = etched(dot(uv + pan * 0.5, normalize(float2(-0.68, 0.74))) * 42.0, 0.40);
    float ridgeB = etched(dot(uv - pan * 0.4, normalize(float2(0.68, 0.74))) * 30.0, 0.44);
    float g = glarePoint(uv, p, 0.85, 1.5);
    float3 foil = rainbow * (0.18 + ridgeA * 0.30 + ridgeB * 0.14);
    foil += float3(0.42, 0.50, 0.60) * (0.12 + grain * 0.18);
    foil += pastel(phase + 0.2) * 0.18 * (0.5 + 0.5 * sin(length(uv - 0.5 + pan * 0.15) * 80.0));
    foil += float3(0.88, 0.92, 0.96) * g * 0.22;
    return foil * (0.75 + dist * 0.2);
}

// 12 · Interference: wavy noise field with ridges, exclusion blend.
static inline float3 interferenceHolo(float2 uv, float2 p, float2 pan, float dist) {
    float field = fbm(uv * 5.0 + pan * 1.2, 4);
    float phase = dot(uv + pan * 1.7, normalize(float2(0.55, -0.84))) * 3.0 + field * 0.4;
    float ridge = etched(dot(uv + pan * 0.8, normalize(float2(-0.68, 0.74))) * 34.0, 0.39);
    float3 foil = spectrum(phase) * (0.15 + field * 0.32 + ridge * 0.25);
    float ang = atan2(uv.y - p.y, uv.x - p.x) / TAU;
    foil += pastel(ang) * glarePoint(uv, p, 0.9, 1.4) * 0.28;
    foil += float3(0.15, 0.22, 0.35) * (1.0 - dist) * 0.2;
    return foil;
}

} // namespace ck

using namespace ck;

// MARK: - Stitchable entry points (colorEffect)

/// Multi-style foil. `style` is the raw value of `HoloStyle` in Swift.
[[stitchable]] half4 ck_holo(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float style
) {
    if (color.a < 0.004h) { return color; }
    float2 uv = position / max(size, float2(1.0));
    float2 p = resolvePointer(pointer, tilt);
    float2 pan = p - 0.5;
    float dist = clamp(length(pan) * 1.41421356, 0.0, 1.0);
    float3 src = unpremul(color);
    float lum = luma(src);
    float amount = clamp(intensity, 0.0, 1.0);
    float3 foil = float3(0.0);
    float3 result = src;

    switch (int(style + 0.5)) {
        case 0:
            foil = regularHolo(uv, p, pan, dist);
            result = applyScreen(src, foil, amount * 0.85);
            break;
        case 1:
            foil = cosmosHolo(uv, p, pan, time);
            result = applyScreen(src, foil, amount * 0.90);
            break;
        case 2:
            foil = reverseHolo(uv, p, pan);
            result = applyOverlay(src, foil, amount * (0.70 + dist * 0.2));
            break;
        case 3:
            foil = galaxyHolo(uv, p, pan, time);
            result = mix(src, screen(src, clamp(foil, 0.0, 1.0)), amount * (0.45 + lum * 0.55));
            break;
        case 4:
            foil = rainbowHolo(uv, p, pan, time);
            result = applyOverlay(src, foil, amount * 0.88);
            break;
        case 5:
            foil = goldHolo(uv, p, pan, time);
            result = applyOverlay(src, foil, amount * 0.92);
            break;
        case 6:
            foil = amazingHolo(uv, p, pan, time);
            result = applyScreen(src, foil, amount * 0.88);
            break;
        case 7:
            foil = radiantHolo(uv, p, pan, time);
            result = applyOverlay(src, foil, amount * 0.78);
            result = applyScreen(result, foil, amount * 0.18);
            break;
        case 8:
            foil = prismHolo(uv, p, pan);
            result = applyScreen(src, foil, amount * 0.85);
            break;
        case 9:
            foil = pearlHolo(uv, p, pan, lum);
            result = mix(src, overlay(src, foil), amount * 0.75);
            break;
        case 10:
            foil = brushedHolo(uv, p, pan);
            result = mix(src, overlay(src, foil), amount * 0.80);
            break;
        case 11:
            foil = sunpillarHolo(uv, p, pan, dist);
            result = applyExclusion(src, foil, amount * 0.86);
            break;
        default:
            foil = interferenceHolo(uv, p, pan, dist);
            result = applyExclusion(src, foil, amount * 0.80);
            break;
    }
    return premul(result, color.a);
}

/// Soft specular highlight following the pointer (or the tilt).
[[stitchable]] half4 ck_glare(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float radius
) {
    if (color.a < 0.004h) { return color; }
    float2 uv = position / max(size, float2(1.0));
    float2 p = resolvePointer(pointer, tilt);
    float valid = step(0.0, pointer.x) * step(0.0, pointer.y);
    float active = max(valid, smoothstep(0.0, 0.25, length(tilt)));
    float g = glarePoint(uv, p, radius, 1.6);
    float3 src = unpremul(color);
    float3 lit = screen(src, float3(g * 0.9));
    float3 result = mix(src, lit, clamp(intensity * active, 0.0, 1.0));
    return premul(result, color.a);
}

/// Twinkling glitter, denser and brighter on light pixels.
[[stitchable]] half4 ck_sparkle(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float density
) {
    if (color.a < 0.004h) { return color; }
    float2 uv = position / max(size, float2(1.0));
    float2 p = resolvePointer(pointer, tilt);
    float sp = sparkleLayer(uv, density, p, time, 3.0) * 0.7
        + sparkleLayer(uv + 0.011, density * 1.6, p, time, 17.0) * 0.5;
    float3 src = unpremul(color);
    float3 result = src + float3(sp) * intensity * (0.5 + 0.5 * luma(src));
    return premul(result, color.a);
}

/// One light band crossing the card. `progress` 0 → 1 moves it edge to edge.
[[stitchable]] half4 ck_sweep(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity,
    float progress, float width, float angle
) {
    if (color.a < 0.004h) { return color; }
    float2 uv = position / max(size, float2(1.0));
    float a = angle * M_PI_F / 180.0;
    float2 dir = float2(cos(a), sin(a));
    float t = dot(uv - 0.5, dir) + 0.5;
    float center = mix(-width, 1.0 + width, progress);
    float band = pow(1.0 - smoothstep(0.0, width, abs(t - center)), 1.5);
    float3 src = unpremul(color);
    float3 result = screen(src, float3(band * intensity));
    result += spectrum(t * 3.0 + progress) * band * intensity * 0.15;
    return premul(result, color.a);
}

/// Pastel cloudy "holo paper" used as the background of framed cards.
/// Generator: ignores the source colour, keeps its alpha.
[[stitchable]] half4 ck_holoPaper(
    float2 position, half4 color,
    float2 size, float2 tilt, float2 pointer, float time, float intensity, float hue
) {
    float2 uv = position / max(size, float2(1.0));
    float2 pan = resolvePointer(pointer, tilt) - 0.5;
    float clouds = fbm(uv * float2(3.0, 4.0) + pan * 0.3, 5);
    float grain = vnoise(uv * float2(500.0, 700.0)) * 0.08;
    float3 base = float3(0.93, 0.92, 0.91);
    float3 tint = pastel(hue + uv.y * 0.6 + clouds * 0.8 + pan.x * 0.4);
    float mask = 0.25 + 0.55 * smoothstep(0.3, 0.8, uv.y + clouds * 0.3 - 0.2);
    float3 col = mix(base, tint, clamp(intensity, 0.0, 1.0) * mask);
    col = col * (0.95 + grain) - clouds * 0.08;
    return premul(col, color.a);
}
