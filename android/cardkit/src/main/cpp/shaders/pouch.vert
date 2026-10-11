#version 450
// The foil pouch: mouth, flare, peel (lift / roll / rip) in the pouch's own
// frame, then into the world. Port of ck_stage_pouch_vertex.
#include "common.glsl"

const float POUCH_W = 1.0;
const float POUCH_H = 1.86;
const float SEAL = 86.0 / 1904.0;
const float TEAR_LINE = 1.0 - 0.085;
const float ROLL_RADIUS = 0.05;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;

layout(location = 0) out vec3 vWorld;
layout(location = 1) out vec3 vNormal;
layout(location = 2) out vec2 vUV;

float cutX(float xw, float dir) { return dir < 0.5 ? xw : dir < 1.5 ? 1.0 - xw : abs(xw - 0.5) * 2.0; }

void main() {
    vec3 p = inPosition;
    vec3 n = inNormal;
    vec2 uv = inUV;
    float side = object.flags.y;
    float tearV = object.tear.x, cutP = object.tear.z;
    float peelMode = object.peel.x, peelDir = object.peel.y, peelAmt = object.peel.z, fly = object.peel.w;
    float mouthAmt = object.mouth.x, mouthK = object.mouth.y;
    float cutDir = object.cut.y;

    float xw = side > 0.0 ? uv.x : 1.0 - uv.x;
    float xc = cutX(xw, cutDir);
    float torn = tearV < 1.5 ? (cutP >= 0.999 ? 1.0 : 1.0 - smoothstep(cutP - 0.16, cutP, xc)) : 0.0;
    float open_ = mouthK * max(0.4 * torn, mouthAmt)
        * smoothstep(TEAR_LINE - 0.34, TEAR_LINE - 0.02, uv.y)
        * (1.0 - smoothstep(0.42, 0.5, abs(uv.x - 0.5)))
        * (1.0 - smoothstep(1.0 - SEAL - 0.02, 1.0 - SEAL, uv.y));
    p.z += (side > 0.0 ? 0.1 : 0.05) * open_;
    if (peelMode < 0.5 && tearV < 1.5 && mouthAmt > 0.0) {
        float flareS = max(0.0, uv.y - (tearV - 0.05)) * POUCH_H;
        float flareK = mouthAmt * (1.0 - smoothstep(0.36, 0.5, abs(uv.x - 0.5)));
        p.z += 5.5 * flareS * flareS * flareK;
        p.y -= 0.8 * flareS * flareS * flareK;
        float a = atan(11.0 * flareS * flareK);
        n = vec3(n.x, n.y * cos(a) - n.z * sin(a), n.y * sin(a) + n.z * cos(a));
    }
    float wx = side * p.x, wz = side * p.z, wy = p.y;
    float hw = cutDir > 1.5 ? 0.5 : 1.0;
    if (peelMode > 0.5 && peelMode < 1.5) {
        float d = max(0.0, cutP - xc) * POUCH_W * hw;
        wy += peelAmt * (0.015 * d + 0.13 * d * d) / hw;
        wz += peelAmt * peelDir * (0.03 * d + 0.34 * d * d) / hw;
    } else if (peelMode > 1.5 && peelMode < 2.5) {
        float xr = (cutP - 0.5) * POUCH_W - 0.05, s = xr - wx;
        if (s > 0.0) {
            float th = s / ROLL_RADIUS, r = ROLL_RADIUS - wz * 0.9 + 0.005 * th / 6.2832;
            wx = xr - r * sin(th); wz = ROLL_RADIUS + 0.02 - r * cos(th); wy += 0.03 * min(1.0, th);
            vec2 nn = vec2(side * n.x, side * n.z);
            nn = vec2(nn.x * cos(th) + nn.y * sin(th), -nn.x * sin(th) + nn.y * cos(th));
            n.x = side * nn.x; n.z = side * nn.y;
        } else {
            float d = clamp(-s, 0.0, 0.05), k = 1.0 - d / 0.05;
            wz += 0.04 * k * k * step(xc, cutP); wy += 0.03 * k * step(xc, cutP);
        }
    } else if (peelMode > 2.5) {
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
    p = vec3(side * wx, wy, side * wz);

    vec4 world = object.model * vec4(p, 1.0);
    vWorld = world.xyz;
    gl_Position = frame.viewProjection * world;
    mat3 m3 = mat3(object.model[0].xyz, object.model[1].xyz, object.model[2].xyz);
    vNormal = normalize(m3 * n);
    vUV = uv;
}
