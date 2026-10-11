#include "stage_scene.h"
#include <chrono>

namespace ck {

StageScene::StageScene(const StageSettings& s) : settings_(s) {
    rebuildPacks(false);
    layoutCamera();
}

void StageScene::setSettings(const StageSettings& s) {
    StageSettings old = settings_;
    settings_ = s;
    if (settings_.packs != (int)packs_.size()) rebuildPacks(true);
    if (settings_.fov != old.fov || settings_.spacing != old.spacing) layoutCamera();
}

float StageScene::floorLine() const {
    vec4 p = camera_.viewProjection() * vec4(0, pouch::floorY, 0, 1);
    if (p.w <= 0) return 0.72f;
    return 0.5f - (p.y / p.w) * 0.5f;
}

// MARK: - Inputs

void StageScene::resize(float width, float height) {
    viewport_ = {std::max(width, 1.f), std::max(height, 1.f)};
    layoutCamera();
}

void StageScene::setDeviceTilt(float x, float y) { deviceTilt_ = {x, y}; }

void StageScene::pointerMoved(bool active, float x, float y) {
    if (!active) { pointerActive_ = false; return; }
    pointer_ = {x / viewport_.x * 2 - 1, y / viewport_.y * 2 - 1};
    pointerActive_ = true;
}

void StageScene::dragBegan(float x, float y, double now) {
    Drag d; d.start = d.last = {x, y}; d.startTime = d.lastTime = now;
    if (onHint) onHint("");
    if (opening_.phase == Phase::idle) {
        int hit = packAt(x, y);
        if (hit >= 0 && hit == frontIndex() && std::fabs(angle_ - target_) < 0.3f) {
            d.spinning = hit;
            packs_[hit].spinVelocity = 0;
            packs_[hit].spinPitchVelocity = 0;
        }
    }
    drag_ = d;
}

void StageScene::dragChanged(float x, float y, double now) {
    if (!drag_) return;
    Drag& d = *drag_;
    float dx = x - d.last.x, dy = y - d.last.y;
    float dt = std::max(0.001f, (float)(now - d.lastTime));
    d.last = {x, y}; d.lastTime = now;
    d.moved += std::fabs(dx) + std::fabs(dy);
    if (opening_.phase != Phase::idle) {
        if (opening_.phase == Phase::ready || opening_.phase == Phase::cut) cutByHand(dx);
        return;
    }
    if (d.spinning >= 0) {
        float step = dx * 0.011f;
        packs_[d.spinning].spinYaw += step;
        packs_[d.spinning].spinPitch = clampf(packs_[d.spinning].spinPitch + dy * 0.007f, -0.7f, 0.7f);
        d.speed = lerp(d.speed, step / dt, 0.4f);
    } else {
        float perPoint = 1 / std::max(260.f, viewport_.x * 0.32f);
        angle_ -= dx * perPoint;
        d.speed = lerp(d.speed, -dx * perPoint / dt, 0.4f);
    }
}

void StageScene::dragEnded(float x, float y, double now) {
    if (!drag_) return;
    Drag d = *drag_;
    drag_.reset();
    bool isTap = d.moved < 8 && now - d.startTime < 0.45;
    float travel = x - d.start.x;
    if (opening_.phase != Phase::idle) {
        if (isTap || std::fabs(travel) > 40 || opening_.phase == Phase::cut) advanceOpening(travel < 0 ? -1.f : 1.f);
        return;
    }
    if (isTap) {
        int hit = packAt(x, y);
        if (hit < 0) return;
        if (hit == frontIndex() && std::fabs(angle_ - target_) < 0.3f) {
            if (onOpenRequest) onOpenRequest(hit);
        } else {
            bringToFront(hit);
        }
    } else if (d.spinning >= 0) {
        float v = clampf(d.speed, -30, 30);
        packs_[d.spinning].spinVelocity = v;
        packs_[d.spinning].spinTarget = std::round((packs_[d.spinning].spinYaw + v * 0.12f) / (float)M_PI) * (float)M_PI;
    } else {
        velocity_ = d.speed;
        target_ = std::round(angle_ + clampf(d.speed * 0.2f, -2, 2));
    }
}

void StageScene::bringToFront(int index) {
    float n = (float)packs_.size();
    float delta = (float)index - wrapf(std::round(target_), n);
    delta = wrapf(delta + n / 2, n) - n / 2;
    target_ = std::round(target_) + std::round(delta);
}

void StageScene::ray(float x, float y, vec3& origin, vec3& direction) const {
    vec2 ndc{x / viewport_.x * 2 - 1, 1 - y / viewport_.y * 2};
    mat4 inverse = camera_.viewProjection().inverse();
    vec4 near_ = inverse * vec4(ndc.x, ndc.y, 0, 1);
    vec4 far_ = inverse * vec4(ndc.x, ndc.y, 1, 1);
    vec3 a = near_.xyz() / near_.w, b = far_.xyz() / far_.w;
    origin = a; direction = normalize(b - a);
}

int StageScene::packAt(float x, float y) const {
    vec3 origin, direction; ray(x, y, origin, direction);
    vec3 half{pouch::width / 2, pouch::height / 2, 0.09f};
    int bestIndex = -1; float bestT = 0;
    for (size_t i = 0; i < poses_.size(); ++i) {
        const PackPose& pose = poses_[i];
        if (!pose.visible) continue;
        mat4 inverse = pose.model.inverse();
        vec3 o = (inverse * vec4(origin, 1)).xyz();
        vec3 d = (inverse * vec4(direction, 0)).xyz();
        float tMin = -INFINITY, tMax = INFINITY; bool missed = false;
        for (int axis = 0; axis < 3; ++axis) {
            if (std::fabs(d[axis]) < 1e-6f) { if (std::fabs(o[axis]) > half[axis]) { missed = true; break; } }
            else {
                float t1 = (-half[axis] - o[axis]) / d[axis], t2 = (half[axis] - o[axis]) / d[axis];
                if (t1 > t2) std::swap(t1, t2);
                tMin = std::max(tMin, t1); tMax = std::min(tMax, t2);
                if (tMin > tMax) { missed = true; break; }
            }
        }
        if (missed || tMax < 0) continue;
        float t = std::max(tMin, 0.f);
        if (bestIndex < 0 || t < bestT) { bestIndex = (int)i; bestT = t; }
    }
    return bestIndex;
}

// MARK: - Frame

void StageScene::advance(float rawDt) {
    float dt = std::min(rawDt, 0.05f);
    time_ += dt;
    clock_ += dt;
    settleSpins(dt);
    if (!drag_) springStep(angle_, velocity_, target_, 36, dt);
    bool busy = opening_.phase != Phase::idle && opening_.phase != Phase::exit;
    away_ += ((busy ? 1.f : 0.f) - away_) * (1 - std::exp(-dt * 5));
    vec2 wanted = pointerActive_ && !drag_ ? pointer_ : deviceTilt_;
    tilt_ += (wanted - tilt_) * (1 - std::exp(-dt * 4));
    if (std::fabs(target_) > 1000) {
        float turns = std::round(target_ / (float)packs_.size()) * (float)packs_.size();
        target_ -= turns; angle_ -= turns;
    }
    float phase = wrapf(time_ - sweepStart_, 6.5f) / 1.6f;
    sweep_ = time_ >= sweepStart_ && phase < 1 ? lerp(-1.45f, 1.45f, phase * phase * (3 - 2 * phase)) : 9;
    placePacks(dt);
    stepOpening(dt);
    raysLevel_ += (openingPose_.raysOpacity - raysLevel_) * (1 - std::exp(-dt * 2.2f));
    dimLevel_ += (openingPose_.dimOpacity - dimLevel_) * (1 - std::exp(-dt * 3.3f));
    particles_.update(dt);
    if (opening_.phase != lastPhase_) {
        lastPhase_ = opening_.phase;
        if (onPhase) onPhase(opening_.phase);
    }
}

void StageScene::settleSpins(float dt) {
    for (size_t i = 0; i < packs_.size(); ++i) {
        if (drag_ && drag_->spinning == (int)i) continue;
        Pack& p = packs_[i];
        springStep(p.spinYaw, p.spinVelocity, p.spinTarget, 14, dt);
        springStep(p.spinPitch, p.spinPitchVelocity, 0, 26, dt);
        if (std::fabs(p.spinYaw - p.spinTarget) < 1e-4f && std::fabs(p.spinVelocity) < 0.001f) {
            float turns = std::round(p.spinTarget / (2 * (float)M_PI)) * 2 * (float)M_PI;
            p.spinYaw -= turns; p.spinTarget -= turns;
        }
    }
}

void StageScene::placePacks(float dt) {
    int n = (int)packs_.size();
    float step = 2 * (float)M_PI / n;
    bool night = settings_.lighting == Lighting::night;
    poses_.resize(n);
    for (int q = 0; q < n; ++q) {
        Pack& p = packs_[q];
        float slot = (float)q - angle_;
        slot = wrapf(slot + n / 2.f, (float)n) - n / 2.f;
        float theta = slot * step;
        float near_ = std::max(0.f, 1 - std::fabs(slot));
        float ring = radius_ * (1 + 2.4f * away_ * away_);
        float x = std::sin(theta) * ring;
        float z = (std::cos(theta) - 1) * ring * settings_.depth - away_ * 1.6f;
        float y = -away_ * 0.3f;
        float yaw = theta - 0.14f * std::sin(theta) - 0.42f * std::sin(2 * theta);
        float pitch = 0, roll = 0;
        if (settings_.floats) {
            float k = (float)q;
            yaw += 0.06f * std::sin(time_ * 0.6f + k * 1.7f);
            pitch += 0.028f * std::sin(time_ * 0.8f + k * 0.9f);
            roll += 0.014f * std::sin(time_ * 0.5f + k * 2.3f);
            y += 0.024f * std::sin(time_ * 1.05f + k * 1.3f);
        }
        yaw += tilt_.x * 0.32f * settings_.tilt * near_ * (1 - away_);
        pitch += tilt_.y * 0.2f * settings_.tilt * near_ * (1 - away_);
        yaw += p.spinYaw; pitch += p.spinPitch;
        p.pop = std::min(1.f, p.pop + dt * 1.6f);
        float scale_ = 0.35f + 0.65f * ease::backOut(p.pop);
        PackPose& pose = poses_[q];
        pose.model = model({x, y, z}, {pitch, yaw, roll}, scale_);
        pose.position = {x, y, z}; pose.euler = {pitch, yaw, roll}; pose.scale = scale_;
        bool opened = opening_.phase != Phase::idle && q == opening_.pack;
        bool gone = away_ > 0.97f && !opened;
        pose.visible = !gone && !opened;
        float footprint = (std::fabs(std::cos(yaw)) * pouch::width + std::fabs(std::sin(yaw)) * 0.2f + 0.25f) * scale_;
        pose.shadowModel = translation({x, pouch::floorY + 0.002f, z + 0.02f}) * rotationX(-(float)M_PI / 2) * scale(vec3(footprint * 1.15f, 0.5f * scale_, 1));
        pose.shadowOpacity = (night ? 0.7f : 0.42f) * (1 - clamp01(y * 4)) * scale_ * settings_.shadow;
    }
}

void StageScene::layoutCamera() {
    float aspect = viewport_.x / viewport_.y;
    float ht = std::tan(settings_.fov * (float)M_PI / 180 / 2);
    float w = pouch::width, h = pouch::height;
    float distance = std::max(h / 0.6f / (2 * ht), w / (aspect < 1 ? 0.6f : 0.5f) / (2 * ht * aspect));
    radius_ = std::min(2.8f, std::max(1.1f, distance * ht * aspect * (aspect < 1 ? 1.4f : 1.05f))) * settings_.spacing;
    StageCamera cam;
    cam.fovY = settings_.fov * (float)M_PI / 180;
    cam.aspect = aspect;
    cam.position = {0, 0.26f, distance};
    cam.target = {0, aspect < 1 ? 0.05f : -0.2f, -0.4f};
    cam.view = lookAt(cam.position, cam.target);
    cam.projection = perspective(cam.fovY, aspect, 0.1f, 60);
    camera_ = cam;
}

void StageScene::rebuildPacks(bool popping) {
    int n = settings_.packs;
    packs_.clear();
    for (int i = 0; i < n; ++i) { Pack p; p.index = i; p.pop = popping ? -(float)i * 0.11f : 1; packs_.push_back(p); }
    if ((int)poses_.size() != n) {
        float wrapped = wrapf(std::round(target_), (float)n);
        angle_ = wrapped; target_ = wrapped; velocity_ = 0;
    }
    placePacks(0);
}

} // namespace ck
