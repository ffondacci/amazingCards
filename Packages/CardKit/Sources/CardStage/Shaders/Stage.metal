//
//  Stage.metal
//  CardKit · CardStage
//
//  The booster stage: foil pouches lit by a studio of light panels, their
//  reflection in the floor and their shadow, and the pieces of a pouch
//  being opened (tear line, peel, mouth, melt, zip). The shading follows
//  three.js's physical material (GGX, Smith, multiscatter, clear coat,
//  ACES), which the look was designed on; the room is analytic instead of
//  a prefiltered cube.
//

#include <metal_stdlib>
using namespace metal;

namespace ckstage {

constant float RECIP_PI = 0.31830988618379;

// Pouch proportions, mirrored from PouchMetrics.
constant float POUCH_W = 1.0;
constant float POUCH_H = 1.86;
constant float SEAL = 86.0 / 1904.0;
constant float TEAR_LINE = 1.0 - 0.085;
constant float TEETH = 38.0;
constant float TOOTH_DEPTH = 0.0056;
constant float2 NOTCH = float2(0.022, 0.014);
constant float ROLL_RADIUS = 0.05;

struct FrameUniforms {
    float4x4 viewProjection;
    float4 cameraPosition;
    float4 lightDirection;
    float4 lightColor;
    float4 params;   // time, sweep, night, floorY
    float4 look;     // foil, holo, gloss, shine
    float4 reflect;  // fade, reflK, wrinkle scale, 0
    float4 screen;   // floor line, rays, halo, dim
    float4 screen2;  // premium, width, height, flash
};

struct ObjectUniforms {
    float4x4 model;
    float4 flags;    // reflect, side, zig, opacity
    float4 tear;     // tearV, tearSide, cutP, inside
    float4 cut;      // lineMode, cutDir, perf, heat
    float4 glow;     // tipGlow, dissolve, innerGlow, guide
    float4 peel;     // peel, peelDir, peelAmt, fly
    float4 mouth;    // mouth, mouthK, card, cardEmissive
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
};

struct PouchVarying {
    float4 clip [[position]];
    float3 world;
    float3 normal;
    float2 uv;
};

// MARK: - Helpers

static inline float sat(float x) { return clamp(x, 0.0, 1.0); }
static inline float pow2f(float x) { return x * x; }

static inline float3 F_Schlick(float3 f0, float f90, float dotVH) {
    float f = pow(1.0 - dotVH, 5.0);
    return f0 * (1.0 - f) + float3(f90 * f);
}
static inline float V_GGX(float alpha, float dotNL, float dotNV) {
    float a2 = pow2f(alpha);
    float gv = dotNL * sqrt(a2 + (1.0 - a2) * pow2f(dotNV));
    float gl = dotNV * sqrt(a2 + (1.0 - a2) * pow2f(dotNL));
    return 0.5 / max(gv + gl, 1e-6);
}
static inline float D_GGX(float alpha, float dotNH) {
    float a2 = pow2f(alpha);
    float d = (dotNH * a2 - dotNH) * dotNH + 1.0;
    return RECIP_PI * a2 / pow2f(d);
}
static inline float3 BRDF_GGX(float3 l, float3 v, float3 n, float3 f0, float f90, float roughness) {
    float alpha = pow2f(roughness);
    float3 h = normalize(l + v);
    float dotNL = sat(dot(n, l)), dotNV = sat(dot(n, v));
    float dotNH = sat(dot(n, h)), dotVH = sat(dot(v, h));
    float3 F = F_Schlick(f0, f90, dotVH);
    return F * (V_GGX(alpha, dotNL, dotNV) * D_GGX(alpha, dotNH));
}
static inline float2 DFGApprox(float dotNV, float roughness) {
    const float4 c0 = float4(-1.0, -0.0275, -0.572, 0.022);
    const float4 c1 = float4(1.0, 0.0425, 1.04, -0.04);
    float4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * dotNV)) * r.x + r.y;
    return float2(-1.04, 1.04) * a004 + r.zw;
}
static inline float3 EnvironmentBRDF(float dotNV, float3 f0, float f90, float roughness) {
    float2 fab = DFGApprox(dotNV, roughness);
    return f0 * fab.x + f90 * fab.y;
}

static inline float3 hue2rgb(float h) {
    return clamp(abs(fmod(h * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}
static inline float hash1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
static inline float noise1(float x) {
    float i = floor(x), f = fract(x);
    return mix(hash1(i), hash1(i + 1.0), f * f * (3.0 - 2.0 * f)) * 2.0 - 1.0;
}
static inline float hash2(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
static inline float noise2(float2 p) {
    float2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + float2(1.0, 0.0)), u.x), mix(hash2(i + float2(0.0, 1.0)), hash2(i + float2(1.0, 1.0)), u.x), u.y) * 2.0 - 1.0;
}

/// Jagged tear line, as a v offset from the straight line.
static inline float tearLine(float x) {
    return 0.0055 * noise1(x * 4.3 + 3.1) + 0.0028 * noise1(x * 13.0 + 1.7) + 0.0014 * noise1(x * 41.0 + 7.9)
         + 0.0007 * noise1(x * 130.0 + 5.3) + 0.00045 * noise1(x * 410.0) + 0.003 * (x - 0.5);
}
/// Cut progress coordinate along the line for the three cut directions.
static inline float cutX(float xw, float dir) { return dir < 0.5 ? xw : dir < 1.5 ? 1.0 - xw : abs(xw - 0.5) * 2.0; }
static inline float lineShape(float x, float lineMode) {
    if (lineMode < 1.5) { return tearLine(x); }
    if (lineMode < 2.5) { return 0.0045 * sin(x * 7.0 + 1.3) + 0.002 * sin(x * 19.0 + 0.4); }
    return -0.0012 * abs(sin(x * 3.14159265 * 40.0));
}

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

// MARK: - The room

struct Panel {
    float3 position;
    float2 size;
    float3 color;
    float intensity;
};

constant Panel STUDIO[6] = {
    { float3(-4.0, 5.0, 6.5),   float2(6.0, 4.0),   float3(1.0),                  5.0 },
    { float3(0.0, 8.5, 0.0),    float2(11.0, 3.5),  float3(1.0),                  2.2 },
    { float3(-7.5, 0.5, 2.0),   float2(1.6, 10.0),  float3(1.0),                  3.4 },
    { float3(7.5, 1.5, 2.5),    float2(1.4, 10.0),  float3(1.0),                  2.2 },
    { float3(0.0, 3.0, -7.5),   float2(6.0, 3.0),   float3(0.894, 0.925, 1.0),    1.6 },
    { float3(0.0, -5.5, 3.0),   float2(9.0, 3.0),   float3(1.0),                  1.0 },
};
constant Panel NIGHT[7] = {
    { float3(-7.5, 1.0, 1.5),   float2(1.6, 10.0),  float3(1.0, 0.247, 0.345),    3.2 },
    { float3(7.5, 1.5, 1.5),    float2(1.6, 10.0),  float3(0.165, 0.847, 1.0),    3.2 },
    { float3(0.0, 8.0, 1.0),    float2(9.0, 2.8),   float3(0.416, 0.467, 1.0),    2.0 },
    { float3(2.8, 3.6, 7.5),    float2(3.4, 1.5),   float3(1.0),                  4.0 },
    { float3(-3.2, -3.0, 6.5),  float2(4.5, 1.3),   float3(1.0, 0.533, 0.667),    1.8 },
    { float3(-3.5, 2.5, -7.0),  float2(4.0, 3.0),   float3(0.541, 0.361, 1.0),    1.4 },
    { float3(0.0, 1.0, 9.0),    float2(9.0, 5.0),   float3(0.784, 0.831, 1.0),    0.55 },
};

static inline float3 roomSky(float3 d, bool night) {
    float3 top = night ? float3(0.06, 0.08, 0.17) : float3(0.48, 0.50, 0.54);
    float3 mid = night ? float3(0.03, 0.035, 0.07) : float3(0.32, 0.33, 0.36);
    float3 bot = night ? float3(0.006, 0.006, 0.014) : float3(0.11, 0.11, 0.12);
    float y = d.y;
    return y > 0.0 ? mix(mid, top, smoothstep(0.0, 0.8, y)) : mix(mid, bot, smoothstep(0.0, 0.5, -y));
}

/// Radiance of one panel seen along `d`, blurred by the roughness.
static inline float3 panelRadiance(Panel p, float3 d, float roughness) {
    float dist = length(p.position);
    float3 toward = p.position / dist;
    float facing = dot(d, toward);
    if (facing <= 0.001) { return float3(0.0); }
    float3 hit = d * (dist / facing) - p.position;
    float3 z = -toward;
    // A panel straight overhead is parallel to the up axis: pick another
    // reference, or the frame is NaN and the panel floods half the picture.
    float3 ref = abs(toward.y) > 0.99 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
    float3 x = normalize(cross(ref, z));
    float3 y = cross(z, x);
    float u = dot(hit, x), v = dot(hit, y);
    float blur = max(0.9, roughness * roughness * dist * 2.2);
    float cov = smoothstep(-blur, blur, p.size.x * 0.5 - abs(u)) * smoothstep(-blur, blur, p.size.y * 0.5 - abs(v));
    float energy = (p.size.x * p.size.y) / ((p.size.x + 2.0 * blur) * (p.size.y + 2.0 * blur));
    return p.color * (p.intensity * cov * energy);
}

/// What a mirror of the given roughness sees in direction `d`.
static inline float3 roomRadiance(float3 d, float roughness, bool night) {
    float3 c = roomSky(d, night);
    if (night) {
        for (int i = 0; i < 7; ++i) { c += panelRadiance(NIGHT[i], d, roughness); }
    } else {
        for (int i = 0; i < 6; ++i) { c += panelRadiance(STUDIO[i], d, roughness); }
    }
    return c;
}

/// Cosine-weighted light arriving on a surface facing `n`.
static inline float3 roomIrradiance(float3 n, bool night) {
    float3 top = night ? float3(0.06, 0.08, 0.17) : float3(0.48, 0.50, 0.54);
    float3 mid = night ? float3(0.03, 0.035, 0.07) : float3(0.32, 0.33, 0.36);
    float3 bot = night ? float3(0.006, 0.006, 0.014) : float3(0.11, 0.11, 0.12);
    float3 c = mix(mid, n.y > 0.0 ? top : bot, abs(n.y) * 0.6);
    if (night) {
        for (int i = 0; i < 7; ++i) {
            Panel p = NIGHT[i];
            float dist2 = dot(p.position, p.position);
            c += p.color * p.intensity * (p.size.x * p.size.y / dist2) * max(0.0, dot(n, p.position * rsqrt(dist2))) * RECIP_PI;
        }
    } else {
        for (int i = 0; i < 6; ++i) {
            Panel p = STUDIO[i];
            float dist2 = dot(p.position, p.position);
            c += p.color * p.intensity * (p.size.x * p.size.y / dist2) * max(0.0, dot(n, p.position * rsqrt(dist2))) * RECIP_PI;
        }
    }
    return c;
}

/// Physical shading of a point: base colour, metalness, roughness, clear
/// coat, two normals (shaded and clear coat) and an emissive term.
static inline float3 shade(float3 base, float metalness, float roughness, float clearcoat, float clearcoatRoughness, float3 emissive,
                           float3 Ns, float3 Ncc, float3 V, constant FrameUniforms &frame, bool night) {
    float3 diffuseColor = base * (1.0 - metalness);
    float3 specularColor = mix(float3(0.04), base, metalness);
    float dotNV = sat(dot(Ns, V));
    float ccDotNV = sat(dot(Ncc, V));
    float3 L = normalize(frame.lightDirection.xyz);
    float3 lightColor = frame.lightColor.rgb * frame.lightDirection.w;
    float dotNL = sat(dot(Ns, L));
    float3 irradiance = dotNL * lightColor;
    float3 directDiffuse = irradiance * (RECIP_PI * diffuseColor);
    float3 directSpecular = irradiance * BRDF_GGX(L, V, Ns, specularColor, 1.0, roughness);
    float ccDotNL = sat(dot(Ncc, L));
    float3 clearcoatDirect = (ccDotNL * lightColor) * BRDF_GGX(L, V, Ncc, float3(0.04), 1.0, clearcoatRoughness);
    float3 R = reflect(-V, Ns);
    float3 irradianceEnv = roomIrradiance(Ns, night);
    float3 radiance = roomRadiance(R, roughness, night);
    float2 fab = DFGApprox(dotNV, roughness);
    float3 FssEss = specularColor * fab.x + float3(fab.y);
    float Ess = fab.x + fab.y;
    float Ems = 1.0 - Ess;
    float3 Favg = specularColor + (float3(1.0) - specularColor) * 0.047619;
    float3 Fms = FssEss * Favg / (float3(1.0) - Ems * Favg);
    float3 single = FssEss;
    float3 multi = Fms * Ems;
    float3 indirectDiffuse = irradianceEnv * (RECIP_PI * diffuseColor);
    indirectDiffuse += diffuseColor * (float3(1.0) - (single + multi)) * irradianceEnv;
    float3 indirectSpecular = radiance * single + multi * irradianceEnv;
    float3 ccR = reflect(-V, Ncc);
    float3 clearcoatIndirect = roomRadiance(ccR, clearcoatRoughness, night) * EnvironmentBRDF(ccDotNV, float3(0.04), 1.0, clearcoatRoughness);
    float3 outgoing = directDiffuse + indirectDiffuse + directSpecular + indirectSpecular + emissive;
    float3 Fcc = F_Schlick(float3(0.04), 1.0, ccDotNV);
    return outgoing * (1.0 - clearcoat * Fcc) + (clearcoatDirect + clearcoatIndirect) * clearcoat;
}

} // namespace ckstage

using namespace ckstage;

// MARK: - Pouch

vertex PouchVarying ck_stage_pouch_vertex(
    VertexIn in [[stage_in]],
    constant FrameUniforms &frame [[buffer(1)]],
    constant ObjectUniforms &object [[buffer(2)]]
) {
    float3 p = in.position;
    float3 n = in.normal;
    float2 uv = in.uv;
    float side = object.flags.y;
    float tearV = object.tear.x, cutP = object.tear.z;
    float peelMode = object.peel.x, peelDir = object.peel.y, peelAmt = object.peel.z, fly = object.peel.w;
    float mouthAmt = object.mouth.x, mouthK = object.mouth.y;
    float cutDir = object.cut.y;

    // Mouth: the body bulges open under the tear line, more where it is torn.
    float xw = side > 0.0 ? uv.x : 1.0 - uv.x;
    float xc = cutX(xw, cutDir);
    float torn = tearV < 1.5 ? (cutP >= 0.999 ? 1.0 : 1.0 - smoothstep(cutP - 0.16, cutP, xc)) : 0.0;
    float open = mouthK * max(0.4 * torn, mouthAmt)
        * smoothstep(TEAR_LINE - 0.34, TEAR_LINE - 0.02, uv.y)
        * (1.0 - smoothstep(0.42, 0.5, abs(uv.x - 0.5)))
        * (1.0 - smoothstep(1.0 - SEAL - 0.02, 1.0 - SEAL, uv.y));
    p.z += (side > 0.0 ? 0.1 : 0.05) * open;
    if (peelMode < 0.5 && tearV < 1.5 && mouthAmt > 0.0) {
        // The lips flare outward above the line.
        float flareS = max(0.0, uv.y - (tearV - 0.05)) * POUCH_H;
        float flareK = mouthAmt * (1.0 - smoothstep(0.36, 0.5, abs(uv.x - 0.5)));
        p.z += 5.5 * flareS * flareS * flareK;
        p.y -= 0.8 * flareS * flareS * flareK;
        float a = atan(11.0 * flareS * flareK);
        n = float3(n.x, n.y * cos(a) - n.z * sin(a), n.y * sin(a) + n.z * cos(a));
    }
    // Peeling of the strip, in the pouch's own frame (x mirrored for the back).
    float wx = side * p.x, wz = side * p.z, wy = p.y;
    float hw = cutDir > 1.5 ? 0.5 : 1.0;
    if (peelMode > 0.5 && peelMode < 1.5) {
        // Lift: the torn part curls up and back.
        float d = max(0.0, cutP - xc) * POUCH_W * hw;
        wy += peelAmt * (0.015 * d + 0.13 * d * d) / hw;
        wz += peelAmt * peelDir * (0.03 * d + 0.34 * d * d) / hw;
    } else if (peelMode > 1.5 && peelMode < 2.5) {
        // Roll: the torn part winds around a cylinder travelling with the cut.
        float xr = (cutP - 0.5) * POUCH_W - 0.05, s = xr - wx;
        if (s > 0.0) {
            float th = s / ROLL_RADIUS, r = ROLL_RADIUS - wz * 0.9 + 0.005 * th / 6.2832;
            wx = xr - r * sin(th); wz = ROLL_RADIUS + 0.02 - r * cos(th); wy += 0.03 * min(1.0, th);
            float2 nn = float2(side * n.x, side * n.z);
            nn = float2(nn.x * cos(th) + nn.y * sin(th), -nn.x * sin(th) + nn.y * cos(th));
            n.x = side * nn.x; n.z = side * nn.y;
        } else {
            float d = clamp(-s, 0.0, 0.05), k = 1.0 - d / 0.05;
            wz += 0.04 * k * k * step(xc, cutP); wy += 0.03 * k * step(xc, cutP);
        }
    } else if (peelMode > 2.5) {
        // Rip: the two halves lift away from the middle, then fly.
        float d = max(0.0, cutP - xc) * POUCH_W * 0.5, sd = wx < 0.0 ? -1.0 : 1.0;
        wy += 0.02 * d + 0.3 * d * d;
        wz += 0.05 * d + 0.5 * d * d;
        wx += sd * 0.06 * d;
        if (fly > 0.0) {
            float cx = sd * 0.25 * POUCH_W, cy = (TEAR_LINE - 0.5) * POUCH_H + 0.05, a = -sd * fly * 2.2;
            float px = wx - cx, py = wy - cy;
            wx = cx + px * cos(a) - py * sin(a) + sd * fly * 1.7;
            wy = cy + px * sin(a) + py * cos(a) + fly * 0.7 - fly * fly * 1.9;
            wz += fly * 0.35;
        }
    }
    p = float3(side * wx, wy, side * wz);

    PouchVarying out;
    float4 world = object.model * float4(p, 1.0);
    out.world = world.xyz;
    out.clip = frame.viewProjection * world;
    float3x3 m3 = float3x3(object.model[0].xyz, object.model[1].xyz, object.model[2].xyz);
    out.normal = normalize(m3 * n);
    out.uv = uv;
    return out;
}

fragment float4 ck_stage_pouch_fragment(
    PouchVarying in [[stage_in]],
    constant FrameUniforms &frame [[buffer(1)]],
    constant ObjectUniforms &object [[buffer(2)]],
    texture2d<float> art [[texture(0)]],
    texture2d<float> mask [[texture(1)]],
    texture2d<float> wrinkleMap [[texture(2)]],
    sampler artSampler [[sampler(0)]],
    bool frontFacing [[front_facing]]
) {
    float2 uv = in.uv;
    bool night = frame.params.z > 0.5;
    bool reflected = object.flags.x > 0.5;
    // A mirrored pouch is drawn through its back faces, which are its front.
    bool front = frontFacing != reflected;
    bool isCard = object.mouth.z > 0.5;
    float side = object.flags.y;
    float tearV = object.tear.x, tearSide = object.tear.y, cutP = object.tear.z, inside = object.tear.w;
    float lineMode = object.cut.x, cutDir = object.cut.y, perf = object.cut.z, heat = object.cut.w;
    float tipGlow = object.glow.x, dissolve = object.glow.y, innerGlow = object.glow.z, guide = object.glow.w;
    float time = frame.params.x;

    float xw = side > 0.0 ? uv.x : 1.0 - uv.x;
    float xc = cutX(xw, cutDir);

    // Crimped seals: zig-zag edges and the side notches at the tear line.
    float coverage = 1.0, edge = 1e3, dT = 1e3;
    if (object.flags.z > 0.5) {
        float tri = abs(fract(uv.x * TEETH) - 0.5) * 2.0;
        float zd = min((1.0 - TOOTH_DEPTH * tri) - uv.y, uv.y - TOOTH_DEPTH * tri) * POUCH_H;
        float nx = min(uv.x, 1.0 - uv.x) * POUCH_W;
        float ny = abs(uv.y - TEAR_LINE) * POUCH_H;
        float nd = nx - NOTCH.x * (1.0 - ny / NOTCH.y);
        coverage = sat(0.5 + zd / max(fwidth(zd), 1e-5)) * sat(0.5 + nd / max(fwidth(nd), 1e-5));
    }
    // Tear line: the body keeps what is under it, the strip what is above.
    if (tearV < 1.5) {
        dT = (uv.y - (tearV + lineShape(xw, lineMode))) * POUCH_H;
        float fT = max(fwidth(dT), 1e-5);
        if (xc < cutP || cutP >= 0.999) {
            edge = abs(dT);
            coverage *= sat(0.5 + (tearSide > 0.5 ? dT : -dT) / fT);
        } else if (tearSide > 0.5) {
            discard_fragment();
        } else if (cutP > 0.001 && lineMode < 1.5) {
            edge = abs(dT) + (xc - cutP) * 0.5;
        }
        if (cutDir > 1.5 && tearSide > 0.5) {
            // Rip: the strip also splits down the middle.
            float cx = (abs(xw - 0.5) - 0.0095 - 0.0015 * noise1(uv.y * 260.0)) * POUCH_W;
            edge = min(edge, abs(cx));
            coverage *= sat(0.5 + cx / max(fwidth(cx), 1e-5));
        }
    }
    // Melt: the strip dissolves.
    float dis = 1e3;
    if (dissolve > 0.0) {
        float dn = noise2(uv * float2(9.0, 40.0)) * 0.55 + noise2(uv * float2(31.0, 120.0)) * 0.3 + noise2(uv * float2(97.0, 300.0)) * 0.15;
        dis = (dn * 0.5 + 0.5) + 0.06 - dissolve * 1.15;
        coverage *= sat(0.5 + dis / max(fwidth(dis), 1e-5));
    }
    if (coverage <= 0.0) { discard_fragment(); }
    // Inside of the pouch: only through the open mouth.
    if (!front) {
        bool ok = inside > 0.5 && abs(uv.x - 0.5) < 0.47 && (xc < cutP - 0.01 || cutP >= 0.999)
            && uv.y > tearV - 0.16 && uv.y < 1.0 - SEAL - 0.012;
        if (!ok) { discard_fragment(); }
    }

    float alpha = coverage * object.flags.w;
    if (reflected) {
        float below = frame.params.w - in.world.y;
        if (below < 0.0) { discard_fragment(); }
        float f = 1.0 - smoothstep(0.0, frame.reflect.x, below);
        alpha *= f * f * frame.reflect.y;
        if (alpha < 0.003) { discard_fragment(); }
    }

    float3 N = normalize(in.normal);
    if (!front) { N = -N; }
    float3 V = normalize(frame.cameraPosition.xyz - in.world);

    // Wrinkles: tangent frame from the pouch's own axes. Cards are flat.
    float3 T = normalize(cross(float3(0.0, 1.0, 0.0), N));
    float3 B = cross(N, T);
    float3 wn = isCard ? float3(0.0, 0.0, 1.0) : wrinkleMap.sample(artSampler, uv).xyz * 2.0 - 1.0;
    float wrinkleScale = isCard ? 0.0 : frame.reflect.z;
    float3 Ns = normalize(T * (wn.x * wrinkleScale) + B * (wn.y * wrinkleScale) + N * wn.z);
    float3 Ncc = normalize(T * (wn.x * wrinkleScale * 0.5) + B * (wn.y * wrinkleScale * 0.5) + N * wn.z);

    // Pictures are stored top row first; the pouch's v runs bottom to top.
    float2 picture = float2(uv.x, 1.0 - uv.y);
    float4 print = art.sample(artSampler, picture);
    float4 m = mask.sample(artSampler, picture);
    float3 base = print.rgb;

    // Holographic rainbow: hue from the reflection direction, wobbling over the print.
    float3 R = reflect(-V, Ns);
    float2 pq = uv * float2(1.0, POUCH_H / POUCH_W);
    float wob = sin(pq.x * 4.3 + sin(pq.y * 3.1) * 1.7) * 0.5 + sin(pq.y * 5.7 - pq.x * 2.3 + 1.3) * 0.3;
    float hue = dot(R, float3(0.85, 1.35, 0.45)) * 0.62 + wob * 0.6 + pq.y * 0.12;
    float3 rainbow = mix(float3(1.0), hue2rgb(fract(hue)), 0.72);
    float holo = sat(m.g * frame.look.y);
    base = mix(base, base * rainbow * 1.25, holo);

    float metalness = sat(max(m.r * frame.look.x, holo * 0.7));
    float roughness = mix(0.1, 0.6, m.b);
    float clearcoat = isCard ? 0.35 : max(0.01, frame.look.z);
    float clearcoatRoughness = isCard ? 0.24 : 0.06;
    float3 emissive = float3(0.0);
    if (isCard) { emissive = print.rgb * object.mouth.w; }

    // Shine sweep across the foil.
    float2 sq = (uv - 0.5) * float2(POUCH_W, POUCH_H);
    float ss = dot(sq, float2(0.62, 0.78)) - frame.params.y;
    float band = exp(-ss * ss / 0.03) * 0.45 + exp(-ss * ss / 0.0018) * 0.9;
    float facing = sat(dot(Ns, V));
    if (front) {
        emissive += float3(1.0, 0.97, 0.93) * band * frame.look.w * facing * (0.3 + 0.7 * max(m.r, m.g)) * (1.0 - 0.6 * m.b);
    }

    // Zip: a row of perforations along the line.
    if (perf > 0.0 && dT < 1e2 && xc >= cutP) {
        float hole = step(0.5, fract(xw * 40.0 + 0.25)) * (1.0 - smoothstep(0.0012, 0.0026, abs(dT)));
        base = mix(base, float3(0.08, 0.08, 0.1), hole * 0.8 * perf);
        metalness = mix(metalness, 0.0, hole);
    }
    // Guide: a dashed line running along the uncut part.
    if (guide > 0.0 && dT < 1e2 && xc >= cutP && front) {
        float gd = abs(dT + 0.0045);
        float dash = step(0.42, fract(xc * 18.0 - time * 1.4));
        float core = (1.0 - smoothstep(0.0016, 0.0028, gd)) * dash, halo = (1.0 - smoothstep(0.0028, 0.0055, gd)) * dash;
        float3 gc = lineMode > 1.5 && lineMode < 2.5 ? float3(1.0, 0.55, 0.2) : float3(1.0);
        base = mix(base, base * 0.35, halo * 0.6 * guide);
        base = mix(base, gc, core * guide);
        metalness = mix(metalness, 0.0, core * guide);
        emissive += gc * core * 0.9 * guide;
    }
    if (lineMode > 1.5 && lineMode < 2.5) {
        // Melt: scorched rim, hot while cutting.
        float rim = 1.0 - smoothstep(0.0, 0.007, edge);
        float scorch = 1.0 - smoothstep(0.0, 0.034, edge);
        base = mix(base, base * float3(0.42, 0.24, 0.12), scorch * 0.9);
        base = mix(base, float3(0.035, 0.022, 0.018), rim);
        metalness = mix(metalness, 0.0, scorch); roughness = mix(roughness, 0.5, scorch);
        float since = cutP >= 0.999 ? 1.0 : sat((cutP - xc) * 2.5);
        float hot = heat * (1.0 - 0.7 * since);
        float flick = 0.8 + 0.2 * noise2(float2(xw * 70.0, time * 4.0));
        emissive += mix(float3(1.0, 0.16, 0.02), float3(1.0, 0.62, 0.22), rim) * (rim * 1.8 + scorch * 0.45) * hot * flick;
        if (tipGlow > 0.0 && dT < 1e2) {
            float gx = (xc - cutP) * POUCH_W;
            emissive += float3(1.0, 0.78, 0.45) * exp(-(gx * gx + dT * dT) / 0.0006) * 4.0 * tipGlow;
        }
    } else {
        // Torn foil: a whitened fibre edge.
        float pw = (0.0035 + 0.003 * (0.5 + 0.5 * noise1(xw * 90.0))) * (lineMode > 2.5 ? 0.55 : 1.0);
        float white = 1.0 - smoothstep(pw * 0.35, pw, edge);
        if (white > 0.0) {
            float core = 1.0 - smoothstep(0.0, pw * 0.4, edge);
            base = mix(base, float3(0.94, 0.95, 0.97), white * 0.9);
            metalness = mix(mix(metalness, 0.2, white), 1.0, core);
            roughness = mix(roughness, 0.4, white);
        }
    }
    if (!front) {
        // Inside: brushed silver.
        float br = 0.5 + 0.5 * noise1(uv.y * 1400.0 + 3.0 * noise1(uv.x * 9.0));
        base = float3(0.87, 0.88, 0.91) * (0.92 + 0.08 * br);
        metalness = 1.0; roughness = 0.16 + 0.1 * br;
        emissive += float3(1.0, 0.94, 0.84) * innerGlow;
        clearcoat = 0.0;
    }
    if (dissolve > 0.0) {
        float e = 1.0 - smoothstep(0.0, 0.07, dis);
        base = mix(base, float3(0.04, 0.025, 0.02), 1.0 - smoothstep(0.04, 0.16, dis));
        emissive += mix(float3(1.0, 0.2, 0.02), float3(1.0, 0.7, 0.3), e * e) * e * 2.2;
    }

    float3 outgoing = shade(base, metalness, roughness, clearcoat, clearcoatRoughness, emissive, Ns, Ncc, V, frame, night);
    float3 mapped = acesFilmic(outgoing, 1.0);
    return float4(mapped, alpha);
}

// MARK: - Shadow sprite

struct SpriteVarying {
    float4 clip [[position]];
    float2 uv;
};

vertex SpriteVarying ck_stage_sprite_vertex(
    uint vid [[vertex_id]],
    constant FrameUniforms &frame [[buffer(1)]],
    constant ObjectUniforms &object [[buffer(2)]]
) {
    const float2 corners[6] = { float2(-0.5, -0.5), float2(0.5, -0.5), float2(0.5, 0.5), float2(-0.5, -0.5), float2(0.5, 0.5), float2(-0.5, 0.5) };
    float2 c = corners[vid];
    SpriteVarying out;
    out.clip = frame.viewProjection * (object.model * float4(c, 0.0, 1.0));
    out.uv = c + 0.5;
    return out;
}

fragment float4 ck_stage_shadow_fragment(
    SpriteVarying in [[stage_in]],
    constant ObjectUniforms &object [[buffer(2)]]
) {
    float r = length(in.uv - 0.5) * 2.0;
    float a = r < 0.45 ? mix(0.6, 0.24, r / 0.45) : mix(0.24, 0.0, sat((r - 0.45) / 0.55));
    return float4(0.0, 0.0, 0.0, a * object.flags.w);
}

// MARK: - Background

struct BackgroundVarying {
    float4 clip [[position]];
    float2 uv;
};

struct RayWedge {
    float start;
    float width;
    float alpha;
    float pad;
};

vertex BackgroundVarying ck_stage_background_vertex(uint vid [[vertex_id]]) {
    const float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    BackgroundVarying out;
    out.clip = float4(corners[vid], 1.0, 1.0);
    out.uv = corners[vid] * 0.5 + 0.5;
    return out;
}

/// CSS-like radial gradient coverage: 0 at the centre, 1 at the ellipse edge.
static inline float radialT(float2 css, float2 center, float2 radii) {
    float2 d = (css - center) / max(radii, float2(1e-4));
    return length(d);
}

/// Sum of the wedges of one ray layer at `angleDeg` (0 = up, clockwise).
static inline float rayLayer(float angleDeg, constant RayWedge *wedges, int count, float spin) {
    float a = angleDeg - spin;
    a -= 360.0 * floor(a / 360.0);
    float v = 0.0;
    for (int i = 0; i < count; ++i) {
        RayWedge w = wedges[i];
        float t = a - w.start;
        if (t < 0.0 || t > w.width) { continue; }
        float mid = w.width * 0.5;
        v += w.alpha * (1.0 - abs(t - mid) / mid);
    }
    return v;
}

fragment float4 ck_stage_background_fragment(
    BackgroundVarying in [[stage_in]],
    constant FrameUniforms &frame [[buffer(1)]],
    constant RayWedge *coarse [[buffer(3)]],
    constant RayWedge *fine [[buffer(4)]],
    constant int2 &wedgeCounts [[buffer(5)]]
) {
    bool night = frame.params.z > 0.5;
    bool premium = frame.screen2.x > 0.5;
    float2 size = frame.screen2.yz;
    // CSS space: x right, y down, 0…1.
    float2 css = float2(in.uv.x, 1.0 - in.uv.y);
    float floorLine = frame.screen.x;
    float vmax = max(size.x, size.y), vmin = min(size.x, size.y);
    float2 px = css * size;

    float3 c;
    if (night) {
        c = float3(0.016, 0.024, 0.051);
        float t = radialT(css, float2(0.74, 0.12), float2(0.9, 0.7));
        float3 g = t < 0.44 ? mix(float3(0.114, 0.227, 0.549), float3(0.043, 0.075, 0.188), t / 0.44)
                            : mix(float3(0.043, 0.075, 0.188), float3(0.016, 0.024, 0.051), sat((t - 0.44) / 0.56));
        c = g;
        float f = radialT(css, float2(0.5, floorLine), float2(0.5, 0.18));
        c = mix(c, float3(0.275, 0.431, 1.0), 0.32 * sat(1.0 - f));
    } else {
        // Daylight studio: a cool grey sweep, darker overhead, a soft spot
        // behind the packs and a bright pool of light on the floor. Sized on
        // the shorter side so the depth reads on a phone as well as a desktop.
        float2 r = float2(vmin / size.x, vmin / size.y);
        float3 top = float3(0.62, 0.66, 0.74);
        float3 mid = float3(0.80, 0.83, 0.88);
        float3 low = float3(0.90, 0.92, 0.95);
        float y = css.y;
        c = y < floorLine ? mix(top, mid, smoothstep(0.0, floorLine * 0.85, y)) : mix(mid, low, smoothstep(floorLine, 1.0, y));
        float spot = radialT(css, float2(0.5, 0.46), float2(0.62, 0.52) * r);
        c = mix(c, float3(0.96, 0.965, 0.975), (1.0 - smoothstep(0.0, 1.0, spot)) * 0.55);
        float f = radialT(css, float2(0.5, floorLine + 0.02), float2(0.75, 0.16) * r);
        float glow = f < 0.35 ? mix(1.0, 0.75, f / 0.35) : mix(0.75, 0.0, sat((f - 0.35) / 0.65));
        c = mix(c, float3(1.0), glow * 0.9);
        float corner = radialT(css, float2(0.5, 0.5), float2(0.85, 0.85) * r);
        c *= 1.0 - 0.18 * smoothstep(0.55, 1.35, corner);
    }

    // Light rays and halo once the cards are out.
    float raysOpacity = frame.screen.y, haloOpacity = frame.screen.z;
    if (raysOpacity > 0.001 || haloOpacity > 0.001) {
        float3 rayColor = premium ? float3(1.0, 0.784, 0.412) : (night ? float3(0.588, 0.69, 1.0) : float3(1.0, 0.855, 0.588));
        float rayA = premium ? 0.7 : (night ? 0.4 : 0.72);
        float3 haloColor = premium ? float3(1.0, 0.839, 0.541) : (night ? float3(0.463, 0.573, 1.0) : float3(1.0, 0.988, 0.957));
        float haloA = premium ? 0.9 : (night ? 0.42 : 0.95);
        float2 centre = float2(0.5, 0.48) * size;
        float2 d = px - centre;
        float r = length(d);
        // Burst mask: closest-side radial over a 220 vmax box.
        float m = r / (1.1 * vmax);
        float mask = m < 0.08 ? mix(1.0, 0.78, m / 0.08)
                   : m < 0.18 ? mix(0.78, 0.52, (m - 0.08) / 0.10)
                   : m < 0.28 ? mix(0.52, 0.32, (m - 0.18) / 0.10)
                   : m < 0.38 ? mix(0.32, 0.18, (m - 0.28) / 0.10)
                   : m < 0.48 ? mix(0.18, 0.09, (m - 0.38) / 0.10)
                   : m < 0.58 ? mix(0.09, 0.04, (m - 0.48) / 0.10)
                   : m < 0.70 ? mix(0.04, 0.012, (m - 0.58) / 0.12)
                   : m < 0.82 ? mix(0.012, 0.0, (m - 0.70) / 0.12) : 0.0;
        float angle = fmod(atan2(d.x, -d.y) * 57.29578 + 360.0, 360.0);
        float rays = rayLayer(angle, coarse, wedgeCounts.x, frame.params.x * 9.0) * rayA
                   + rayLayer(angle, fine, wedgeCounts.y, -frame.params.x * 22.5) * rayA * 0.7;
        rays = min(1.0, rays * mask) * raysOpacity;
        c = mix(c, rayColor, rays);
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
    // Dim the edges while the rare card waits.
    float dim = frame.screen.w;
    if (dim > 0.001) {
        float t = length(px - 0.5 * size) / (0.9 * vmax);
        float k = sat((t - 0.28) / 0.72) * 0.42 * dim;
        c = mix(c, float3(0.11, 0.063, 0.0), k);
    }
    // Flash of the reveal.
    float flash = frame.screen2.w;
    if (flash > 0.001) {
        float t = length(px - float2(0.5, 0.45) * size) / (0.7 * vmin);
        float3 fc = premium ? (t < 0.45 ? mix(float3(1.0, 0.941, 0.745), float3(1.0, 0.784, 0.353), t / 0.45) : float3(1.0, 0.745, 0.314))
                            : (t < 0.45 ? mix(float3(1.0), float3(1.0, 0.98, 0.92), t / 0.45) : float3(1.0));
        float fa = t < 0.45 ? mix(1.0, premium ? 0.6 : 0.55, t / 0.45) : mix(premium ? 0.6 : 0.55, 0.0, sat((t - 0.45) / 0.55));
        c = mix(c, fc, fa * flash);
    }
    // Values are sRGB like the stylesheet; the target encodes linear.
    return float4(pow(c, float3(2.2)), 1.0);
}
