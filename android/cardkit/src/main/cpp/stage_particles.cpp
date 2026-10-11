#include "stage_particles.h"
#include <cstdlib>

namespace ck {

const vec3 StageParticles::foil{0.949f, 0.949f, 0.973f};
const vec3 StageParticles::foilLight = mix(vec3(1), foil, 0.35f);
const vec3 StageParticles::warm[4] = {{1, 0.86f, 0.45f}, {1, 0.97f, 0.8f}, {1, 0.62f, 0.25f}, {0.7f, 0.9f, 1}};
const vec3 StageParticles::gold[4] = {{1, 0.84f, 0.36f}, {1, 0.95f, 0.7f}, {1, 0.7f, 0.2f}, {1, 1, 0.9f}};
const vec3 StageParticles::burstFlakes[4] = {{1, 0.949f, 0.722f}, {1, 0.839f, 0.42f}, {0.878f, 0.647f, 0.149f}, {1, 1, 1}};

int StageParticles::count(float amount, float dial) {
    float a = amount * std::max(0.f, dial);
    int whole = (int)std::floor(a);
    return whole + (frand() < a - whole ? 1 : 0);
}

void StageParticles::spawnFlake(vec3 p, vec3 v, float size, vec3 color, float life) {
    Flake& f = flakes[nextFlake++ % flakeCount];
    f = Flake();
    f.position = p; f.velocity = v;
    f.rotation = quatEuler({frand() * 6, frand() * 6, frand() * 6});
    f.spin = vec3(frand() - 0.5f, frand() - 0.5f, frand() - 0.5f) * 22.f;
    f.size = size; f.life = life; f.max = life; f.phase = frand() * 6; f.color = color;
}

void StageParticles::flake(vec3 p, float scale) {
    spawnFlake(p + vec3((frand() - 0.5f) * 0.02f, (frand() - 0.3f) * 0.02f, 0.01f),
               vec3((frand() - 0.35f) * 0.4f, 0.15f + frand() * 0.5f, 0.15f + frand() * 0.35f),
               (0.009f + frand() * frand() * 0.024f) * scale,
               frand() < 0.72f ? foil : foilLight,
               1.1f + frand() * 0.9f);
}

void StageParticles::spawnSparks(vec3 p, int n, vec3 spread, float speed, float lift, bool goldPalette) {
    for (int i = 0; i < n; ++i) {
        Spark& k = sparks[nextSpark++ % sparkCount];
        float a = frand() * 2 * (float)M_PI, t = std::acos(2 * frand() - 1), s = speed * (0.35f + frand() * 0.65f);
        k = Spark();
        k.position = p + vec3((frand() - 0.5f) * spread.x, (frand() - 0.5f) * spread.y, (frand() - 0.5f) * spread.z);
        k.velocity = vec3(std::cos(a) * std::sin(t) * s, std::cos(t) * s * 0.6f + lift * s, std::sin(a) * std::sin(t) * s * 0.5f);
        k.life = 0.45f + frand() * 0.7f; k.max = k.life;
        const vec3* palette = goldPalette ? gold : warm;
        k.color = palette[(int)(frand() * 4) % 4];
    }
}

void StageParticles::puff(vec3 p) {
    Puff& q = puffs[nextPuff++ % puffCount];
    q = Puff();
    q.position = p;
    q.velocity = vec3((frand() - 0.5f) * 0.12f, 0.22f + frand() * 0.22f, 0.04f + frand() * 0.1f);
    q.life = 1.3f + frand() * 0.9f; q.max = q.life;
    q.size = 0.05f + frand() * 0.05f; q.spin = (frand() - 0.5f) * 1.2f; q.angle = frand() * 2 * (float)M_PI;
}

void StageParticles::update(float dt) {
    clock += dt;
    for (Flake& f : flakes) {
        if (f.life <= 0) continue;
        f.life -= dt;
        f.velocity.y -= 1.5f * dt;
        f.velocity *= std::exp(-dt * 2.2f);
        f.velocity.x += std::sin(clock * 5 + f.phase) * 0.9f * dt;
        f.position += f.velocity * dt;
        f.rotation = f.rotation * quatEuler(f.spin * dt);
    }
    float drag = std::pow(0.985f, dt * 60);
    for (Spark& k : sparks) {
        if (k.life <= 0) continue;
        k.life -= dt;
        k.velocity.y -= 2.4f * dt;
        k.velocity *= drag;
        k.position += k.velocity * dt;
    }
    for (Puff& q : puffs) {
        if (q.life <= 0) continue;
        q.life -= dt;
        q.velocity.x *= std::exp(-dt * 0.8f);
        q.position += q.velocity * dt;
        q.angle += q.spin * dt;
    }
}

} // namespace ck
