#version 450
#include "common.glsl"
layout(location = 0) in vec3 vNormal;
layout(location = 1) in vec3 vWorld;
layout(location = 2) in vec4 vColor;
layout(location = 0) out vec4 outColor;
void main() {
    vec3 N = normalize(vNormal);
    if (!gl_FrontFacing) { N = -N; }
    vec3 V = normalize(frame.cameraPosition.xyz - vWorld);
    vec3 L = normalize(frame.lightDirection.xyz);
    float diffuse = 0.35 + 0.65 * sat(dot(N, L));
    vec3 H = normalize(L + V);
    float spec = pow(sat(dot(N, H)), 48.0) * 1.6;
    float fres = pow(1.0 - sat(dot(N, V)), 3.0);
    bool night = frame.params.z > 0.5;
    vec3 env = night ? vec3(0.25, 0.3, 0.5) : vec3(1.3);
    vec3 c = vColor.rgb * (diffuse * frame.lightDirection.w * 0.6 + 0.45 * env) + vec3(spec) * frame.lightColor.rgb + vec3(0.25) * fres * env;
    c += vec3(0.23, 0.23, 0.25) * 0.5;
    outColor = vec4(acesFilmic(c, 1.0), 1.0);
}
