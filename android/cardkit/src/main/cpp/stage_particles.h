// Flakes of foil, sparks and smoke flying around an opening, a port of
// StageParticles.swift: fixed pools, simulated every frame.
#pragma once
#include <vector>
#include "stage_math.h"

namespace ck {

struct StageParticles {
    struct Flake { vec3 position, velocity; quat rotation; vec3 spin; float size = 0, life = 0, max = 1, phase = 0; vec3 color{1, 1, 1}; };
    struct Spark { vec3 position, velocity; float life = 0, max = 1; vec3 color{1, 1, 1}; };
    struct Puff { vec3 position, velocity; float life = 0, max = 1, size = 0, spin = 0, angle = 0; };

    static constexpr int flakeCount = 360, sparkCount = 260, puffCount = 60;
    std::vector<Flake> flakes = std::vector<Flake>(flakeCount);
    std::vector<Spark> sparks = std::vector<Spark>(sparkCount);
    std::vector<Puff> puffs = std::vector<Puff>(puffCount);

    static const vec3 foil, foilLight;
    static const vec3 warm[4], gold[4], burstFlakes[4];

    int count(float amount, float dial);
    void spawnFlake(vec3 p, vec3 v, float size, vec3 color, float life);
    void flake(vec3 p, float scale = 1);
    void spawnSparks(vec3 p, int n, vec3 spread, float speed, float lift = 0.6f, bool gold = false);
    void puff(vec3 p);
    void update(float dt);
    static float scaleOf(const Flake& f) { return f.life > 0 ? f.size * std::min(1.f, f.life / 0.3f) : 0; }
    static float alphaOf(const Spark& k) { return k.life > 0 ? std::pow(std::min(1.f, std::max(0.f, k.life / k.max)), 1.3f) : 0; }
    static void lookOf(const Puff& q, float& size, float& opacity) {
        if (q.life <= 0) { size = 0; opacity = 0; return; }
        float age = 1 - q.life / q.max;
        size = q.size + age * 0.42f;
        opacity = 0.55f * std::sin((float)M_PI * std::min(1.f, age * 1.15f)) * (1 - age * 0.5f);
    }

private:
    int nextFlake = 0, nextSpark = 0, nextPuff = 0;
    float clock = 0;
};

} // namespace ck
