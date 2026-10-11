//
//  StageEffects.metal
//  CardKit · CardStage
//
//  The small things flying around an opening: foil flakes (instanced,
//  lit), sparks and smoke (billboards), and the glow and light rays behind
//  the rare card.
//

#include <metal_stdlib>
using namespace metal;

namespace ckfx {

struct FrameUniforms {
    float4x4 viewProjection;
    float4 cameraPosition;
    float4 lightDirection;
    float4 lightColor;
    float4 params;
    float4 look;
    float4 reflect;
    float4 screen;   // floor line, rays, halo, dim
    float4 screen2;  // premium, width, height, flash
};

struct ObjectUniforms {
    float4x4 model;
    float4 flags;
    float4 tear;
    float4 cut;
    float4 glow;
    float4 peel;
    float4 mouth;
};

struct FlakeInstance {
    float4x4 model;
    float4 color;
};

struct SpriteInstance {
    float4 position;   // xyz, size
    float4 color;      // rgb, alpha
    float4 extra;      // angle, kind (0 spark, 1 smoke), 0, 0
};

static inline float sat(float x) { return clamp(x, 0.0, 1.0); }
static inline float hash1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

static inline float3 acesFilmic(float3 color_in, float exposure) {
    float3x3 IN = float3x3(float3(0.59719, 0.07600, 0.02840),
                           float3(0.35458, 0.90834, 0.13383),
                           float3(0.04823, 0.01566, 0.83777));
    float3x3 OUT = float3x3(float3(1.60475, -0.10208, -0.00327),
                            float3(-0.53108, 1.10813, -0.07276),
                            float3(-0.07367, -0.00605, 1.07602));
    float3 color = color_in * (exposure / 0.6);
    color = IN * color;
    float3 a = color * (color + float3(0.0245786)) - float3(0.000090537);
    float3 b = color * (0.983729 * color + float3(0.4329510)) + float3(0.238081);
    color = OUT * (a / b);
    return clamp(color, float3(0.0), float3(1.0));
}

} // namespace ckfx

using namespace ckfx;

// MARK: - Flakes

struct FlakeVarying {
    float4 clip [[position]];
    float3 normal;
    float3 world;
    float4 color;
};

vertex FlakeVarying ck_stage_flake_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms &frame [[buffer(1)]],
    constant FlakeInstance *instances [[buffer(3)]]
) {
    const float2 shape[4] = { float2(-0.5, -0.35), float2(0.55, -0.5), float2(0.35, 0.45), float2(-0.4, 0.5) };
    const uint order[6] = { 0, 1, 2, 0, 2, 3 };
    float2 c = shape[order[vid]];
    FlakeInstance inst = instances[iid];
    float4 world = inst.model * float4(c, 0.0, 1.0);
    FlakeVarying out;
    out.clip = frame.viewProjection * world;
    out.world = world.xyz;
    float3x3 m3 = float3x3(inst.model[0].xyz, inst.model[1].xyz, inst.model[2].xyz);
    out.normal = normalize(m3 * float3(0.0, 0.0, 1.0));
    out.color = inst.color;
    return out;
}

fragment float4 ck_stage_flake_fragment(
    FlakeVarying in [[stage_in]],
    constant FrameUniforms &frame [[buffer(1)]],
    bool frontFacing [[front_facing]]
) {
    float3 N = normalize(in.normal);
    if (!frontFacing) { N = -N; }
    float3 V = normalize(frame.cameraPosition.xyz - in.world);
    float3 L = normalize(frame.lightDirection.xyz);
    float diffuse = 0.35 + 0.65 * sat(dot(N, L));
    float3 H = normalize(L + V);
    float spec = pow(sat(dot(N, H)), 48.0) * 1.6;
    float fres = pow(1.0 - sat(dot(N, V)), 3.0);
    bool night = frame.params.z > 0.5;
    float3 env = night ? float3(0.25, 0.3, 0.5) : float3(1.3);
    float3 c = in.color.rgb * (diffuse * frame.lightDirection.w * 0.6 + 0.45 * env) + float3(spec) * frame.lightColor.rgb + float3(0.25) * fres * env;
    c += float3(0.23, 0.23, 0.25) * 0.5;
    return float4(acesFilmic(c, 1.0), 1.0);
}

// MARK: - Sprites (sparks, smoke)

struct SpriteVarying {
    float4 clip [[position]];
    float2 uv;
    float4 color;
    float kind;
};

vertex SpriteVarying ck_stage_particle_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms &frame [[buffer(1)]],
    constant SpriteInstance *instances [[buffer(3)]]
) {
    const float2 corners[6] = { float2(-0.5, -0.5), float2(0.5, -0.5), float2(0.5, 0.5), float2(-0.5, -0.5), float2(0.5, 0.5), float2(-0.5, 0.5) };
    SpriteInstance inst = instances[iid];
    float2 c = corners[vid];
    float a = inst.extra.x;
    float2 r = float2(c.x * cos(a) - c.y * sin(a), c.x * sin(a) + c.y * cos(a)) * inst.position.w;
    // Billboard: offset in the camera's plane.
    float3 toCamera = normalize(frame.cameraPosition.xyz - inst.position.xyz);
    float3 right = normalize(cross(float3(0.0, 1.0, 0.0), toCamera));
    float3 up = cross(toCamera, right);
    float3 world = inst.position.xyz + right * r.x + up * r.y;
    SpriteVarying out;
    out.clip = frame.viewProjection * float4(world, 1.0);
    out.uv = c + 0.5;
    out.color = inst.color;
    out.kind = inst.extra.y;
    return out;
}

fragment float4 ck_stage_particle_fragment(SpriteVarying in [[stage_in]]) {
    float r = length(in.uv - 0.5) * 2.0;
    float a;
    if (in.kind < 0.5) {
        a = r < 0.3 ? mix(1.0, 0.7, r / 0.3) : mix(0.7, 0.0, sat((r - 0.3) / 0.7));
    } else {
        a = r < 0.45 ? mix(0.6, 0.22, r / 0.45) : mix(0.22, 0.0, sat((r - 0.45) / 0.55));
    }
    a *= in.color.a;
    if (a < 0.002) { discard_fragment(); }
    return float4(in.color.rgb * a, a);
}

// MARK: - Aura (glow and rays behind the rare card)

struct AuraVarying {
    float4 clip [[position]];
    float2 uv;
};

vertex AuraVarying ck_stage_aura_vertex(
    uint vid [[vertex_id]],
    constant FrameUniforms &frame [[buffer(1)]],
    constant ObjectUniforms &object [[buffer(2)]]
) {
    const float2 corners[6] = { float2(-0.5, -0.5), float2(0.5, -0.5), float2(0.5, 0.5), float2(-0.5, -0.5), float2(0.5, 0.5), float2(-0.5, 0.5) };
    float2 c = corners[vid];
    AuraVarying out;
    out.clip = frame.viewProjection * (object.model * float4(c, 0.0, 1.0));
    out.uv = c;
    return out;
}

/// flags.w = opacity, flags.z = rays (1) or glow (0).
fragment float4 ck_stage_aura_fragment(
    AuraVarying in [[stage_in]],
    constant ObjectUniforms &object [[buffer(2)]]
) {
    float2 p = in.uv * 2.0;
    float r = length(p);
    float opacity = object.flags.w;
    if (object.flags.z < 0.5) {
        float3 c = r < 0.35 ? mix(float3(1.0, 0.84, 0.43), float3(1.0, 0.745, 0.275), r / 0.35) : float3(1.0, 0.69, 0.18);
        float a = r < 0.35 ? mix(0.95, 0.5, r / 0.35) : mix(0.5, 0.0, sat((r - 0.35) / 0.65));
        return float4(c * a * opacity, a * opacity);
    }
    // Rays: three layers of wedges around the centre.
    float angle = atan2(p.y, p.x);
    float total = 0.0;
    float3 color = float3(0.0);
    const float scales[3] = { 2.4, 1.5, 1.0 };
    const float alphas[3] = { 0.18, 0.32, 0.55 };
    for (int l = 0; l < 3; ++l) {
        float seed = 5.0 + float(l) * 31.0;
        for (int w = 0; w < 22; ++w) {
            float k = float(w);
            float centre = (k + hash1(seed + k * 1.7) * 0.8) * 6.2831853 / 22.0;
            float width = (0.01 + hash1(seed + k * 2.3 + 1.0) * 0.03) * scales[l];
            float len = 0.5 + hash1(seed + k * 3.1 + 2.0) * 0.5;
            float d = angle - centre;
            d = d - 6.2831853 * round(d / 6.2831853);
            float wedge = 1.0 - smoothstep(width * 0.6, width, abs(d));
            if (wedge <= 0.0) { continue; }
            float t = r / len;
            float a = t < 0.45 ? mix(1.0, 0.45, t / 0.45) : mix(0.45, 0.0, sat((t - 0.45) / 0.55));
            float3 c = t < 0.45 ? mix(float3(1.0, 0.91, 0.63), float3(1.0, 0.81, 0.43), t / 0.45) : float3(1.0, 0.745, 0.275);
            float contribution = wedge * a * alphas[l];
            color += c * contribution;
            total += contribution;
        }
    }
    total = min(total, 1.0);
    return float4(color * opacity, total * opacity);
}
