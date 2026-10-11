#version 450
// Foil, holo, seals, tear line, melt, inside, reflection: the physical
// shading of Stage.metal (three.js material on an analytic room).
#include "common.glsl"

layout(set = 0, binding = 2) uniform sampler2D wrinkleMap;
layout(set = 1, binding = 0) uniform sampler2D art;
layout(set = 1, binding = 1) uniform sampler2D maskTex;

layout(location = 0) in vec3 vWorld;
layout(location = 1) in vec3 vNormal;
layout(location = 2) in vec2 vUV;
layout(location = 0) out vec4 outColor;

const float RECIP_PI = 0.31830988618379;
const float POUCH_W = 1.0;
const float POUCH_H = 1.86;
const float SEAL = 86.0 / 1904.0;
const float TEAR_LINE = 1.0 - 0.085;
const float TEETH = 38.0;
const float TOOTH_DEPTH = 0.0056;
const vec2 NOTCH = vec2(0.022, 0.014);

float pow2f(float x) { return x * x; }
vec3 F_Schlick(vec3 f0, float f90, float dotVH) { float f = pow(1.0 - dotVH, 5.0); return f0 * (1.0 - f) + vec3(f90 * f); }
float V_GGX(float alpha, float dotNL, float dotNV) {
    float a2 = pow2f(alpha);
    float gv = dotNL * sqrt(a2 + (1.0 - a2) * pow2f(dotNV));
    float gl = dotNV * sqrt(a2 + (1.0 - a2) * pow2f(dotNL));
    return 0.5 / max(gv + gl, 1e-6);
}
float D_GGX(float alpha, float dotNH) { float a2 = pow2f(alpha); float d = (dotNH * a2 - dotNH) * dotNH + 1.0; return RECIP_PI * a2 / pow2f(d); }
vec3 BRDF_GGX(vec3 l, vec3 v, vec3 n, vec3 f0, float f90, float roughness) {
    float alpha = pow2f(roughness);
    vec3 h = normalize(l + v);
    float dotNL = sat(dot(n, l)), dotNV = sat(dot(n, v));
    float dotNH = sat(dot(n, h)), dotVH = sat(dot(v, h));
    vec3 F = F_Schlick(f0, f90, dotVH);
    return F * (V_GGX(alpha, dotNL, dotNV) * D_GGX(alpha, dotNH));
}
vec2 DFGApprox(float dotNV, float roughness) {
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
    vec4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * dotNV)) * r.x + r.y;
    return vec2(-1.04, 1.04) * a004 + r.zw;
}
vec3 EnvironmentBRDF(float dotNV, vec3 f0, float f90, float roughness) { vec2 fab = DFGApprox(dotNV, roughness); return f0 * fab.x + f90 * fab.y; }
vec3 hue2rgb(float h) { return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }
float noise1(float x) { float i = floor(x), f = fract(x); return mix(hash1(i), hash1(i + 1.0), f * f * (3.0 - 2.0 * f)) * 2.0 - 1.0; }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
    vec2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y) * 2.0 - 1.0;
}
float tearLine(float x) {
    return 0.0055 * noise1(x * 4.3 + 3.1) + 0.0028 * noise1(x * 13.0 + 1.7) + 0.0014 * noise1(x * 41.0 + 7.9)
         + 0.0007 * noise1(x * 130.0 + 5.3) + 0.00045 * noise1(x * 410.0) + 0.003 * (x - 0.5);
}
float cutX(float xw, float dir) { return dir < 0.5 ? xw : dir < 1.5 ? 1.0 - xw : abs(xw - 0.5) * 2.0; }
float lineShape(float x, float lineMode) {
    if (lineMode < 1.5) { return tearLine(x); }
    if (lineMode < 2.5) { return 0.0045 * sin(x * 7.0 + 1.3) + 0.002 * sin(x * 19.0 + 0.4); }
    return -0.0012 * abs(sin(x * 3.14159265 * 40.0));
}

// The room: light panels, written out one by one. Adreno puts a constant
// struct array indexed in a loop into scratch memory, which made every
// pouch fragment a hundred times slower; explicit calls keep it in registers.
vec3 roomSky(vec3 d, bool night) {
    vec3 top = night ? vec3(0.06, 0.08, 0.17) : vec3(0.48, 0.50, 0.54);
    vec3 mid = night ? vec3(0.03, 0.035, 0.07) : vec3(0.32, 0.33, 0.36);
    vec3 bot = night ? vec3(0.006, 0.006, 0.014) : vec3(0.11, 0.11, 0.12);
    float y = d.y;
    return y > 0.0 ? mix(mid, top, smoothstep(0.0, 0.8, y)) : mix(mid, bot, smoothstep(0.0, 0.5, -y));
}
vec3 panelRadiance(vec3 position, vec2 size, vec3 color, float intensity, vec3 d, float roughness) {
    float dist = length(position);
    vec3 toward = position / dist;
    float facing = dot(d, toward);
    if (facing <= 0.001) { return vec3(0.0); }
    vec3 hit = d * (dist / facing) - position;
    vec3 z = -toward;
    vec3 ref = abs(toward.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
    vec3 x = normalize(cross(ref, z));
    vec3 y = cross(z, x);
    float u = dot(hit, x), v = dot(hit, y);
    float blur = max(0.9, roughness * roughness * dist * 2.2);
    float cov = smoothstep(-blur, blur, size.x * 0.5 - abs(u)) * smoothstep(-blur, blur, size.y * 0.5 - abs(v));
    float energy = (size.x * size.y) / ((size.x + 2.0 * blur) * (size.y + 2.0 * blur));
    return color * (intensity * cov * energy);
}
vec3 roomRadiance(vec3 d, float roughness, bool night) {
    vec3 c = roomSky(d, night);
    if (night) {
        c += panelRadiance(vec3(-7.5, 1.0, 1.5),  vec2(1.6, 10.0), vec3(1.0, 0.247, 0.345), 3.2, d, roughness);
        c += panelRadiance(vec3(7.5, 1.5, 1.5),   vec2(1.6, 10.0), vec3(0.165, 0.847, 1.0), 3.2, d, roughness);
        c += panelRadiance(vec3(0.0, 8.0, 1.0),   vec2(9.0, 2.8),  vec3(0.416, 0.467, 1.0), 2.0, d, roughness);
        c += panelRadiance(vec3(2.8, 3.6, 7.5),   vec2(3.4, 1.5),  vec3(1.0),               4.0, d, roughness);
        c += panelRadiance(vec3(-3.2, -3.0, 6.5), vec2(4.5, 1.3),  vec3(1.0, 0.533, 0.667), 1.8, d, roughness);
        c += panelRadiance(vec3(-3.5, 2.5, -7.0), vec2(4.0, 3.0),  vec3(0.541, 0.361, 1.0), 1.4, d, roughness);
        c += panelRadiance(vec3(0.0, 1.0, 9.0),   vec2(9.0, 5.0),  vec3(0.784, 0.831, 1.0), 0.55, d, roughness);
    } else {
        c += panelRadiance(vec3(-4.0, 5.0, 6.5),  vec2(6.0, 4.0),  vec3(1.0),               5.0, d, roughness);
        c += panelRadiance(vec3(0.0, 8.5, 0.0),   vec2(11.0, 3.5), vec3(1.0),               2.2, d, roughness);
        c += panelRadiance(vec3(-7.5, 0.5, 2.0),  vec2(1.6, 10.0), vec3(1.0),               3.4, d, roughness);
        c += panelRadiance(vec3(7.5, 1.5, 2.5),   vec2(1.4, 10.0), vec3(1.0),               2.2, d, roughness);
        c += panelRadiance(vec3(0.0, 3.0, -7.5),  vec2(6.0, 3.0),  vec3(0.894, 0.925, 1.0), 1.6, d, roughness);
        c += panelRadiance(vec3(0.0, -5.5, 3.0),  vec2(9.0, 3.0),  vec3(1.0),               1.0, d, roughness);
    }
    return c;
}
vec3 panelIrradiance(vec3 position, vec2 size, vec3 color, float intensity, vec3 n) {
    float dist2 = dot(position, position);
    return color * intensity * (size.x * size.y / dist2) * max(0.0, dot(n, position * inversesqrt(dist2))) * RECIP_PI;
}
vec3 roomIrradiance(vec3 n, bool night) {
    vec3 top = night ? vec3(0.06, 0.08, 0.17) : vec3(0.48, 0.50, 0.54);
    vec3 mid = night ? vec3(0.03, 0.035, 0.07) : vec3(0.32, 0.33, 0.36);
    vec3 bot = night ? vec3(0.006, 0.006, 0.014) : vec3(0.11, 0.11, 0.12);
    vec3 c = mix(mid, n.y > 0.0 ? top : bot, abs(n.y) * 0.6);
    if (night) {
        c += panelIrradiance(vec3(-7.5, 1.0, 1.5),  vec2(1.6, 10.0), vec3(1.0, 0.247, 0.345), 3.2, n);
        c += panelIrradiance(vec3(7.5, 1.5, 1.5),   vec2(1.6, 10.0), vec3(0.165, 0.847, 1.0), 3.2, n);
        c += panelIrradiance(vec3(0.0, 8.0, 1.0),   vec2(9.0, 2.8),  vec3(0.416, 0.467, 1.0), 2.0, n);
        c += panelIrradiance(vec3(2.8, 3.6, 7.5),   vec2(3.4, 1.5),  vec3(1.0),               4.0, n);
        c += panelIrradiance(vec3(-3.2, -3.0, 6.5), vec2(4.5, 1.3),  vec3(1.0, 0.533, 0.667), 1.8, n);
        c += panelIrradiance(vec3(-3.5, 2.5, -7.0), vec2(4.0, 3.0),  vec3(0.541, 0.361, 1.0), 1.4, n);
        c += panelIrradiance(vec3(0.0, 1.0, 9.0),   vec2(9.0, 5.0),  vec3(0.784, 0.831, 1.0), 0.55, n);
    } else {
        c += panelIrradiance(vec3(-4.0, 5.0, 6.5),  vec2(6.0, 4.0),  vec3(1.0),               5.0, n);
        c += panelIrradiance(vec3(0.0, 8.5, 0.0),   vec2(11.0, 3.5), vec3(1.0),               2.2, n);
        c += panelIrradiance(vec3(-7.5, 0.5, 2.0),  vec2(1.6, 10.0), vec3(1.0),               3.4, n);
        c += panelIrradiance(vec3(7.5, 1.5, 2.5),   vec2(1.4, 10.0), vec3(1.0),               2.2, n);
        c += panelIrradiance(vec3(0.0, 3.0, -7.5),  vec2(6.0, 3.0),  vec3(0.894, 0.925, 1.0), 1.6, n);
        c += panelIrradiance(vec3(0.0, -5.5, 3.0),  vec2(9.0, 3.0),  vec3(1.0),               1.0, n);
    }
    return c;
}
vec3 shade(vec3 base, float metalness, float roughness, float clearcoat, float clearcoatRoughness, vec3 emissive, vec3 Ns, vec3 Ncc, vec3 V, bool night) {
    vec3 diffuseColor = base * (1.0 - metalness);
    vec3 specularColor = mix(vec3(0.04), base, metalness);
    float dotNV = sat(dot(Ns, V));
    float ccDotNV = sat(dot(Ncc, V));
    vec3 L = normalize(frame.lightDirection.xyz);
    vec3 lightColor = frame.lightColor.rgb * frame.lightDirection.w;
    float dotNL = sat(dot(Ns, L));
    vec3 irradiance = dotNL * lightColor;
    vec3 directDiffuse = irradiance * (RECIP_PI * diffuseColor);
    vec3 directSpecular = irradiance * BRDF_GGX(L, V, Ns, specularColor, 1.0, roughness);
    float ccDotNL = sat(dot(Ncc, L));
    vec3 clearcoatDirect = (ccDotNL * lightColor) * BRDF_GGX(L, V, Ncc, vec3(0.04), 1.0, clearcoatRoughness);
    vec3 R = reflect(-V, Ns);
    vec3 irradianceEnv = roomIrradiance(Ns, night);
    vec3 radiance = roomRadiance(R, roughness, night);
    vec2 fab = DFGApprox(dotNV, roughness);
    vec3 FssEss = specularColor * fab.x + vec3(fab.y);
    float Ess = fab.x + fab.y;
    float Ems = 1.0 - Ess;
    vec3 Favg = specularColor + (vec3(1.0) - specularColor) * 0.047619;
    vec3 Fms = FssEss * Favg / (vec3(1.0) - Ems * Favg);
    vec3 single = FssEss;
    vec3 multi = Fms * Ems;
    vec3 indirectDiffuse = irradianceEnv * (RECIP_PI * diffuseColor);
    indirectDiffuse += diffuseColor * (vec3(1.0) - (single + multi)) * irradianceEnv;
    vec3 indirectSpecular = radiance * single + multi * irradianceEnv;
    vec3 ccR = reflect(-V, Ncc);
    vec3 clearcoatIndirect = roomRadiance(ccR, clearcoatRoughness, night) * EnvironmentBRDF(ccDotNV, vec3(0.04), 1.0, clearcoatRoughness);
    vec3 outgoing = directDiffuse + indirectDiffuse + directSpecular + indirectSpecular + emissive;
    vec3 Fcc = F_Schlick(vec3(0.04), 1.0, ccDotNV);
    return outgoing * (1.0 - clearcoat * Fcc) + (clearcoatDirect + clearcoatIndirect) * clearcoat;
}

void main() {
    vec2 uv = vUV;
    bool night = frame.params.z > 0.5;
    bool reflected = object.flags.x > 0.5;
    bool front = gl_FrontFacing != reflected;
    bool isCard = object.mouth.z > 0.5;
    float side = object.flags.y;
    float tearV = object.tear.x, tearSide = object.tear.y, cutP = object.tear.z, inside = object.tear.w;
    float lineMode = object.cut.x, cutDir = object.cut.y, perf = object.cut.z, heat = object.cut.w;
    float tipGlow = object.glow.x, dissolve = object.glow.y, innerGlow = object.glow.z, guide = object.glow.w;
    float time = frame.params.x;

    float xw = side > 0.0 ? uv.x : 1.0 - uv.x;
    float xc = cutX(xw, cutDir);

    float coverage = 1.0, edge = 1e3, dT = 1e3;
    if (object.flags.z > 0.5) {
        float tri = abs(fract(uv.x * TEETH) - 0.5) * 2.0;
        float zd = min((1.0 - TOOTH_DEPTH * tri) - uv.y, uv.y - TOOTH_DEPTH * tri) * POUCH_H;
        float nx = min(uv.x, 1.0 - uv.x) * POUCH_W;
        float ny = abs(uv.y - TEAR_LINE) * POUCH_H;
        float nd = nx - NOTCH.x * (1.0 - ny / NOTCH.y);
        coverage = sat(0.5 + zd / max(fwidth(zd), 1e-5)) * sat(0.5 + nd / max(fwidth(nd), 1e-5));
    }
    if (tearV < 1.5) {
        dT = (uv.y - (tearV + lineShape(xw, lineMode))) * POUCH_H;
        float fT = max(fwidth(dT), 1e-5);
        if (xc < cutP || cutP >= 0.999) {
            edge = abs(dT);
            coverage *= sat(0.5 + (tearSide > 0.5 ? dT : -dT) / fT);
        } else if (tearSide > 0.5) {
            discard;
        } else if (cutP > 0.001 && lineMode < 1.5) {
            edge = abs(dT) + (xc - cutP) * 0.5;
        }
        if (cutDir > 1.5 && tearSide > 0.5) {
            float cx = (abs(xw - 0.5) - 0.0095 - 0.0015 * noise1(uv.y * 260.0)) * POUCH_W;
            edge = min(edge, abs(cx));
            coverage *= sat(0.5 + cx / max(fwidth(cx), 1e-5));
        }
    }
    float dis = 1e3;
    if (dissolve > 0.0) {
        float dn = noise2(uv * vec2(9.0, 40.0)) * 0.55 + noise2(uv * vec2(31.0, 120.0)) * 0.3 + noise2(uv * vec2(97.0, 300.0)) * 0.15;
        dis = (dn * 0.5 + 0.5) + 0.06 - dissolve * 1.15;
        coverage *= sat(0.5 + dis / max(fwidth(dis), 1e-5));
    }
    if (coverage <= 0.0) { discard; }
    if (!front) {
        bool ok = inside > 0.5 && abs(uv.x - 0.5) < 0.47 && (xc < cutP - 0.01 || cutP >= 0.999)
            && uv.y > tearV - 0.16 && uv.y < 1.0 - SEAL - 0.012;
        if (!ok) { discard; }
    }

    float alpha = coverage * object.flags.w;
    if (reflected) {
        float below = frame.params.w - vWorld.y;
        if (below < 0.0) { discard; }
        float f = 1.0 - smoothstep(0.0, frame.reflectK.x, below);
        alpha *= f * f * frame.reflectK.y;
        if (alpha < 0.003) { discard; }
    }

    vec3 N = normalize(vNormal);
    if (!front) { N = -N; }
    vec3 V = normalize(frame.cameraPosition.xyz - vWorld);

    vec3 T = normalize(cross(vec3(0.0, 1.0, 0.0), N));
    vec3 B = cross(N, T);
    vec3 wn = isCard ? vec3(0.0, 0.0, 1.0) : texture(wrinkleMap, uv).xyz * 2.0 - 1.0;
    float wrinkleScale = isCard ? 0.0 : frame.reflectK.z;
    vec3 Ns = normalize(T * (wn.x * wrinkleScale) + B * (wn.y * wrinkleScale) + N * wn.z);
    vec3 Ncc = normalize(T * (wn.x * wrinkleScale * 0.5) + B * (wn.y * wrinkleScale * 0.5) + N * wn.z);

    vec2 picture = vec2(uv.x, 1.0 - uv.y);
    vec4 print = texture(art, picture);
    vec4 m = texture(maskTex, picture);
    vec3 base = print.rgb;

    vec3 R = reflect(-V, Ns);
    vec2 pq = uv * vec2(1.0, POUCH_H / POUCH_W);
    float wob = sin(pq.x * 4.3 + sin(pq.y * 3.1) * 1.7) * 0.5 + sin(pq.y * 5.7 - pq.x * 2.3 + 1.3) * 0.3;
    float hue = dot(R, vec3(0.85, 1.35, 0.45)) * 0.62 + wob * 0.6 + pq.y * 0.12;
    vec3 rainbow = mix(vec3(1.0), hue2rgb(fract(hue)), 0.72);
    float holo = sat(m.g * frame.look.y);
    base = mix(base, base * rainbow * 1.25, holo);

    float metalness = sat(max(m.r * frame.look.x, holo * 0.7));
    float roughness = mix(0.1, 0.6, m.b);
    float clearcoat = isCard ? 0.35 : max(0.01, frame.look.z);
    float clearcoatRoughness = isCard ? 0.24 : 0.06;
    vec3 emissive = vec3(0.0);
    if (isCard) { emissive = print.rgb * object.mouth.w; }

    vec2 sq = (uv - 0.5) * vec2(POUCH_W, POUCH_H);
    float ss = dot(sq, vec2(0.62, 0.78)) - frame.params.y;
    float band = exp(-ss * ss / 0.03) * 0.45 + exp(-ss * ss / 0.0018) * 0.9;
    float facing = sat(dot(Ns, V));
    if (front) {
        emissive += vec3(1.0, 0.97, 0.93) * band * frame.look.w * facing * (0.3 + 0.7 * max(m.r, m.g)) * (1.0 - 0.6 * m.b);
    }

    if (perf > 0.0 && dT < 1e2 && xc >= cutP) {
        float hole = step(0.5, fract(xw * 40.0 + 0.25)) * (1.0 - smoothstep(0.0012, 0.0026, abs(dT)));
        base = mix(base, vec3(0.08, 0.08, 0.1), hole * 0.8 * perf);
        metalness = mix(metalness, 0.0, hole);
    }
    if (guide > 0.0 && dT < 1e2 && xc >= cutP && front) {
        float gd = abs(dT + 0.0045);
        float dash = step(0.42, fract(xc * 18.0 - time * 1.4));
        float core = (1.0 - smoothstep(0.0016, 0.0028, gd)) * dash, halo = (1.0 - smoothstep(0.0028, 0.0055, gd)) * dash;
        vec3 gc = lineMode > 1.5 && lineMode < 2.5 ? vec3(1.0, 0.55, 0.2) : vec3(1.0);
        base = mix(base, base * 0.35, halo * 0.6 * guide);
        base = mix(base, gc, core * guide);
        metalness = mix(metalness, 0.0, core * guide);
        emissive += gc * core * 0.9 * guide;
    }
    if (lineMode > 1.5 && lineMode < 2.5) {
        float rim = 1.0 - smoothstep(0.0, 0.007, edge);
        float scorch = 1.0 - smoothstep(0.0, 0.034, edge);
        base = mix(base, base * vec3(0.42, 0.24, 0.12), scorch * 0.9);
        base = mix(base, vec3(0.035, 0.022, 0.018), rim);
        metalness = mix(metalness, 0.0, scorch); roughness = mix(roughness, 0.5, scorch);
        float since = cutP >= 0.999 ? 1.0 : sat((cutP - xc) * 2.5);
        float hot = heat * (1.0 - 0.7 * since);
        float flick = 0.8 + 0.2 * noise2(vec2(xw * 70.0, time * 4.0));
        emissive += mix(vec3(1.0, 0.16, 0.02), vec3(1.0, 0.62, 0.22), rim) * (rim * 1.8 + scorch * 0.45) * hot * flick;
        if (tipGlow > 0.0 && dT < 1e2) {
            float gx = (xc - cutP) * POUCH_W;
            emissive += vec3(1.0, 0.78, 0.45) * exp(-(gx * gx + dT * dT) / 0.0006) * 4.0 * tipGlow;
        }
    } else {
        float pw = (0.0035 + 0.003 * (0.5 + 0.5 * noise1(xw * 90.0))) * (lineMode > 2.5 ? 0.55 : 1.0);
        float white = 1.0 - smoothstep(pw * 0.35, pw, edge);
        if (white > 0.0) {
            float core = 1.0 - smoothstep(0.0, pw * 0.4, edge);
            base = mix(base, vec3(0.94, 0.95, 0.97), white * 0.9);
            metalness = mix(mix(metalness, 0.2, white), 1.0, core);
            roughness = mix(roughness, 0.4, white);
        }
    }
    if (!front) {
        float br = 0.5 + 0.5 * noise1(uv.y * 1400.0 + 3.0 * noise1(uv.x * 9.0));
        base = vec3(0.87, 0.88, 0.91) * (0.92 + 0.08 * br);
        metalness = 1.0; roughness = 0.16 + 0.1 * br;
        emissive += vec3(1.0, 0.94, 0.84) * innerGlow;
        clearcoat = 0.0;
    }
    if (dissolve > 0.0) {
        float e = 1.0 - smoothstep(0.0, 0.07, dis);
        base = mix(base, vec3(0.04, 0.025, 0.02), 1.0 - smoothstep(0.04, 0.16, dis));
        emissive += mix(vec3(1.0, 0.2, 0.02), vec3(1.0, 0.7, 0.3), e * e) * e * 2.2;
    }

    vec3 outgoing = shade(base, metalness, roughness, clearcoat, clearcoatRoughness, emissive, Ns, Ncc, V, night);
    outColor = vec4(acesFilmic(outgoing, 1.0), alpha);
}
