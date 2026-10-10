//
//  Transitions.metal
//  CardKit · CardFX
//
//  Geometry and transition effects: chromatic split (layer), dissolve (color),
//  tear (layer), ripple (distortion).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace ckt {

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

/// Jagged offset of a torn paper edge along the cut. Mirrored in Swift by
/// `TearEdge.offset(at:)` so the split pieces match the shader exactly.
static inline float tearNoise(float x) {
    return sin(x * 0.31 + 1.3) * 0.45 + sin(x * 0.73 + 2.7) * 0.30
        + sin(x * 1.37 + 0.5) * 0.15 + sin(x * 2.9) * 0.10;
}

/// Smooth 1D value noise (−1…1) for the fine fibres of a torn edge.
/// Mirrored in Swift by `TearShader.fibreOffset(at:)`.
static inline float fibreNoise(float x) {
    float a = x * 0.9;
    float b = x * 2.7;
    float ia = floor(a), fa = a - ia;
    float ib = floor(b), fb = b - ib;
    fa = fa * fa * (3.0 - 2.0 * fa);
    fb = fb * fb * (3.0 - 2.0 * fb);
    float na = mix(hash21(float2(ia, 3.0)), hash21(float2(ia + 1.0, 3.0)), fa);
    float nb = mix(hash21(float2(ib, 9.0)), hash21(float2(ib + 1.0, 9.0)), fb);
    return (na * 2.0 - 1.0) * 0.7 + (nb * 2.0 - 1.0) * 0.3;
}

static inline float3 unpremul(half4 c) {
    return c.a > 0.001h ? float3(c.rgb) / float(c.a) : float3(0.0);
}

static inline half4 premul(float3 rgb, half a) {
    return half4(half3(clamp(rgb, 0.0, 1.0)) * a, a);
}

} // namespace ckt

using namespace ckt;

/// RGB split along the tilt direction, `amount` in points.
[[stitchable]] half4 ck_chromatic(
    float2 position, SwiftUI::Layer layer,
    float2 size, float2 tilt, float amount
) {
    float2 offset = tilt * amount;
    half4 r = layer.sample(position + offset);
    half4 g = layer.sample(position);
    half4 b = layer.sample(position - offset);
    return half4(r.r, g.g, b.b, g.a);
}

/// Noise-threshold dissolve with a glowing edge. `progress` 0 = intact, 1 = gone.
[[stitchable]] half4 ck_dissolve(
    float2 position, half4 color,
    float2 size, float progress, float edgeWidth, float3 edgeColor, float scale
) {
    if (color.a < 0.004h || progress <= 0.0005) { return color; }
    float2 uv = position / max(size, float2(1.0));
    float n = fbm(uv * scale, 4) * 1.3 - 0.15;
    float threshold = progress * (1.0 + edgeWidth * 2.0) - edgeWidth;
    if (n < threshold) { return half4(0.0h); }
    float edge = 1.0 - smoothstep(threshold, threshold + edgeWidth, n);
    float3 src = unpremul(color);
    float3 result = mix(src, edgeColor * 1.5, edge);
    return premul(result, color.a);
}

/// Paper tear from `origin` (on an edge) towards `tip` (the finger).
///
/// The body (positive side of the cut) stays put. The strip (negative side)
/// is pulled away by the gap and curls further near the edge. The gap is
/// widest at the origin and closes at the tip. Both torn edges show a
/// fibrous paper core; the lifted strip is shaded and casts a shadow.
[[stitchable]] half4 ck_tear(
    float2 position, SwiftUI::Layer layer,
    float2 size, float2 origin, float2 tip, float gap, float roughness, float lift
) {
    float2 dir = tip - origin;
    float len = length(dir);
    if (len < 1.0 || gap < 0.05) { return layer.sample(position); }
    float2 n = dir / len;
    float2 perp = float2(-n.y, n.x);
    float2 rel = position - origin;
    float along = dot(rel, n);
    float across = dot(rel, perp);
    if (along > len + 6.0) { return layer.sample(position); }

    float clampedAlong = max(along, 0.0);
    float t = clamp(clampedAlong / len, 0.0, 1.0);
    float tipFade = smoothstep(len + 2.0, len - 26.0, along);
    float gapHere = gap * pow(1.0 - t, 0.85) * tipFade;

    // Jagged edge: coarse waves plus smooth fine fibres.
    float jag = tearNoise(clampedAlong) * roughness + fibreNoise(clampedAlong) * roughness * 0.45;
    float d = across + jag;
    bool stripSide = d < 0.0;
    float opening = min(1.0, gapHere / 6.0);

    // Body: untouched, except for the paper core and the shadow of the strip.
    if (!stripSide) {
        half4 sampled = layer.sample(position);
        float3 rgb = unpremul(sampled);
        float fibre = 0.5 + 0.5 * hash21(float2(floor(clampedAlong * 2.3), 11.0));
        float rim = smoothstep(1.4 + fibre * 2.0, 0.0, d) * opening;
        rgb = mix(rgb, float3(0.97, 0.96, 0.93), rim * (0.6 + 0.4 * fibre));
        float shadow = smoothstep(gapHere * 0.9 + 10.0, 0.0, d) * 0.4 * opening;
        rgb *= 1.0 - shadow;
        return premul(rgb, sampled.a);
    }

    // Strip: the band next to the cut is the opening, the rest is pulled away.
    float dist = -d;
    if (dist < gapHere) { return half4(0.0h); }
    float edgeDist = dist - gapHere;
    float curl = lift * gapHere * smoothstep(gapHere * 2.0 + 24.0, 0.0, edgeDist);
    float2 samplePosition = position + perp * (gapHere + curl);
    if (any(samplePosition < float2(0.0)) || any(samplePosition > size)) { return half4(0.0h); }
    half4 sampled = layer.sample(samplePosition);
    float3 rgb = unpremul(sampled);
    float fibre = 0.5 + 0.5 * hash21(float2(floor(clampedAlong * 2.3), 17.0));
    float rim = smoothstep(1.4 + fibre * 2.0, 0.0, edgeDist) * opening;
    rgb = mix(rgb, float3(0.97, 0.96, 0.93), rim * (0.6 + 0.4 * fibre));
    float shade = smoothstep(gapHere + 18.0, 0.0, edgeDist) * 0.3 * opening;
    rgb *= 1.0 - shade;
    return premul(rgb, sampled.a);
}

/// Radial ripple fading with distance and time (seconds since the tap).
[[stitchable]] float2 ck_ripple(
    float2 position,
    float2 size, float2 center, float time, float amplitude, float frequency
) {
    float2 d = position - center;
    float r = length(d);
    float wave = sin(r * frequency - time * 8.0) * amplitude
        * exp(-r / max(size.x * 0.6, 1.0)) * exp(-time * 1.8);
    float2 direction = r > 0.001 ? d / r : float2(0.0);
    return position + direction * wave;
}
