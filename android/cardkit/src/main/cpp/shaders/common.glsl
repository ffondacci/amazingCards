// Shared blocks of the stage shaders. Layouts mirror StageUniforms.swift
// and Stage.metal exactly (std140: a mat4 then vec4s, no padding).
#ifndef CK_COMMON_GLSL
#define CK_COMMON_GLSL

layout(std140, set = 0, binding = 0) uniform FrameUniforms {
    mat4 viewProjection;
    vec4 cameraPosition;
    vec4 lightDirection;   // xyz toward the light, w intensity
    vec4 lightColor;
    vec4 params;           // time, sweep, night, floorY
    vec4 look;             // foil, holo, gloss, shine
    vec4 reflectK;         // fade, reflection strength, wrinkle scale, 0
    vec4 screen;           // floor line, rays, halo, dim
    vec4 screen2;          // premium, width, height, flash
} frame;

layout(std140, set = 0, binding = 1) uniform ObjectUniforms {
    mat4 model;
    vec4 flags;    // reflect, side, zig, opacity
    vec4 tear;     // tearV, tearSide, cutP, inside
    vec4 cut;      // lineMode, cutDir, perf, heat
    vec4 glow;     // tipGlow, dissolve, innerGlow, guide
    vec4 peel;     // peel, peelDir, peelAmt, fly
    vec4 mouth;    // mouth, mouthK, card, cardEmissive
} object;

float sat(float x) { return clamp(x, 0.0, 1.0); }
float hash1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

vec3 acesFilmic(vec3 color_in, float exposure) {
    mat3 IN = mat3(vec3(0.59719, 0.07600, 0.02840),
                   vec3(0.35458, 0.90834, 0.13383),
                   vec3(0.04823, 0.01566, 0.83777));
    mat3 OUT = mat3(vec3(1.60475, -0.10208, -0.00327),
                    vec3(-0.53108, 1.10813, -0.07276),
                    vec3(-0.07367, -0.00605, 1.07602));
    vec3 color = color_in * (exposure / 0.6);
    color = IN * color;
    vec3 a = color * (color + vec3(0.0245786)) - vec3(0.000090537);
    vec3 b = color * (0.983729 * color + vec3(0.4329510)) + vec3(0.238081);
    color = OUT * (a / b);
    return clamp(color, vec3(0.0), vec3(1.0));
}

#endif
