// Every dial of the stage, mirroring StageSettings.swift. Kotlin fills it
// through JNI with the same defaults.
#pragma once

namespace ck {

enum class Lighting : int { studio = 0, night = 1 };
enum class Opening : int { tear = 0, rip = 1, zip = 2, melt = 3, roll = 4, lid = 5 };

struct StageSettings {
    int packs = 5;
    float spacing = 1, depth = 0.82f, fov = 28, tilt = 1;
    bool floats = true;
    float reflection = 1, shadow = 1;
    Lighting lighting = Lighting::studio;
    bool background = true;
    float puff = 0.55f, wrinkles = 0.5f, foil = 1, holo = 1, gloss = 0.8f, shine = 0.55f;
    Opening opening = Opening::tear;
    float speed = 1, hold = 0.3f, autoOpen = 6;
    bool rareLast = true, guide = true, hints = true;
    float particles = 1;
    bool rays = true;
};

/// Pouch proportions, in stage units: one unit wide (PouchMetrics.swift).
namespace pouch {
constexpr float width = 1.f;
constexpr float height = 1.86f;
constexpr float seal = 86.f / 1904.f;
constexpr float tearLine = 1.f - 0.085f;
constexpr float teeth = 38.f;
constexpr float toothDepth = 0.0056f;
constexpr float notchX = 0.022f, notchY = 0.014f;
constexpr float floorY = -height / 2 - 0.1f;
}

} // namespace ck
