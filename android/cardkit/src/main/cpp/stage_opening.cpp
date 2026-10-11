// The opening of the front pack, a port of StageOpening.swift: it flies in
// front of the camera, waits for the swipe, comes apart in the chosen
// style, drops away while the cards rise out, then deals them.
#include "stage_scene.h"

namespace ck {

StageScene::StyleTiming StageScene::timing(Opening s) {
    switch (s) {
        case Opening::tear: return {2.1f, 1.35f, 0.14f, 0.5f, 0.85f};
        case Opening::rip: return {2.1f, 1.3f, 0.14f, 0.5f, 0.85f};
        case Opening::zip: return {2.85f, 1.9f, 0.25f, 0.48f, 0.7f};
        case Opening::melt: return {2.75f, 1.f, 0.2f, 0.48f, 1.f};
        case Opening::roll: return {2.95f, 1.3f, 0.14f, 0.5f, 0.85f};
        case Opening::lid: return {2.05f, 1.f, 0.14f, 0.5f, 1.25f};
    }
    return {2.1f, 1.35f, 0.14f, 0.5f, 0.85f};
}

const char* StageScene::hintFor(Opening s) {
    switch (s) {
        case Opening::tear: return "Swipe across the strip to tear it";
        case Opening::rip: return "Swipe to rip it apart";
        case Opening::zip: return "Swipe to pull the tab";
        case Opening::melt: return "Swipe to melt the seal";
        case Opening::roll: return "Swipe to roll it open";
        case Opening::lid: return "Swipe to lift the lid";
    }
    return "";
}

quat StageScene::cameraRotation() const {
    return quat::fromMatrix(camera_.view.transposed());
}

StageScene::Anchor StageScene::anchorBase() const {
    float aspect = viewport_.x / viewport_.y;
    float ht = halfTan();
    float distance = std::max(pouch::height / 0.84f / (2 * ht), pouch::width / 0.8f / (2 * ht * aspect));
    vec3 forward = normalize(camera_.target - camera_.position);
    return {camera_.position + forward * distance, cameraRotation(), distance, ht * aspect};
}

// MARK: - Start, advance, leave

bool StageScene::open(int index, int cardCount) {
    if (opening_.phase != Phase::idle || index >= (int)poses_.size() || cardCount <= 0) return false;
    dealtCount_ = std::min(5, cardCount);
    const PackPose& pose = poses_[index];
    OpeningState o;
    o.openings = opening_.openings + 1;
    o.pack = index;
    o.phase = Phase::zoom;
    o.style = settings_.opening;
    o.rare = settings_.rareLast && cardCount > 1;
    o.from = pose.position;
    o.fromRotation = quatEuler(pose.euler);
    o.fromScale = pose.scale;
    o.position = o.from; o.rotation = o.fromRotation; o.scale = o.fromScale;
    o.low = 1;
    opening_ = o;
    Pack& p = packs_[index];
    p.spinYaw = p.spinTarget = p.spinVelocity = p.spinPitch = p.spinPitchVelocity = 0;
    show(nullptr);
    openingPose_ = OpeningPose();
    openingPose_.visible = true;
    openingPose_.bodyVisible = true;
    return true;
}

void StageScene::exit() {
    if (opening_.phase == Phase::idle || opening_.phase == Phase::exit) return;
    OpeningState& o = opening_;
    o.exitFrom = o.phase;
    o.exitAt = o.tau;
    o.exitT0 = o.t;
    o.unopened = o.phase == Phase::zoom || o.phase == Phase::ready || o.phase == Phase::cut;
    o.exitPosition = o.position; o.exitRotation = o.rotation; o.exitScale = o.scale;
    o.phase = Phase::exit;
    show(nullptr);
}

void StageScene::advanceOpening(float direction) {
    switch (opening_.phase) {
        case Phase::ready: case Phase::cut:
            opening_.phase = Phase::cut;
            opening_.manual = false;
            break;
        case Phase::present: dealNext(direction); break;
        case Phase::fan: if (opening_.tau > opening_.fanAt + 0.6f) exit(); break;
        default: break;
    }
}

void StageScene::cutByHand(float dx) {
    if (opening_.phase != Phase::ready && opening_.phase != Phase::cut) return;
    float span = viewport_.y * 0.84f * (pouch::width / pouch::height);
    opening_.phase = Phase::cut;
    opening_.manual = true;
    opening_.cut = clamp01(opening_.cut + std::fabs(dx) / (span * (opening_.style == Opening::rip ? 0.5f : 1.f)));
}

void StageScene::dealNext(float direction) {
    OpeningState& o = opening_;
    if (o.phase != Phase::present) return;
    int count = dealtCount_;
    char text[96];
    if (o.top == count - 1) {
        if (o.rare) {
            if (o.revealAt == 0) { if (o.tau >= o.premAt) reveal(); return; }
            if (o.tau < o.revealAt + 1.1f) return;
        }
        o.phase = Phase::fan;
        o.fanAt = o.tau;
        show("Tap to put them away");
        return;
    }
    o.cards[o.top].dealtAt = o.tau;
    o.cards[o.top].direction = direction;
    o.top += 1;
    if (o.top == count - 1) {
        if (o.rare) {
            o.premAt = o.tau + 0.3f;
            show("Something rare is inside · tap to reveal");
        } else {
            snprintf(text, sizeof text, "%d / %d · tap to see them all", count, count);
            show(text);
        }
    } else {
        snprintf(text, sizeof text, "%d / %d · tap for the next card", o.top + 1, count);
        show(text);
    }
}

void StageScene::reveal() {
    if (opening_.revealAt != 0) return;
    opening_.revealAt = opening_.tau;
    opening_.burst = false;
    show("★ tap to see all five");
}

void StageScene::finish(bool reappear) {
    int index = opening_.pack;
    opening_.phase = Phase::idle;
    openingPose_ = OpeningPose();
    if (index < (int)packs_.size()) packs_[index].pop = reappear ? 1 : 0;
    dealtCount_ = 0;
    show("Drag the pack to turn it · tap to open");
}

void StageScene::show(const char* text) {
    hintCleared_ = text == nullptr;
    if (!onHint) return;
    onHint(settings_.hints && text ? std::string(text) : std::string());
}

// MARK: - Frame

void StageScene::stepOpening(float rawDt) {
    if (opening_.phase == Phase::idle) return;
    float dt = rawDt * std::min(4.f, std::max(0.1f, settings_.speed));
    opening_.t += dt;
    Anchor anchor = anchorBase();
    Opening style = opening_.style;
    StyleTiming tm = timing(style);
    OpeningState o = opening_;

    // Held low while being torn, rising as the cards come.
    bool lowWanted = o.phase == Phase::zoom || o.phase == Phase::ready || o.phase == Phase::cut
        || (o.phase == Phase::open && openingPose_.bodyVisible && pieceMotion().bodyPosition.y > -0.1f);
    o.low += ((lowWanted ? 1.f : 0.f) - o.low) * (1 - std::exp(-dt * 4));
    vec3 target = anchor.position;
    vec3 up = anchor.rotation.act({0, 1, 0});
    target += up * (-std::min(0.5f, std::max(0.f, settings_.hold)) * 2 * anchor.distance * halfTan() * o.low);

    // Peek: tilt toward the viewer while cutting and just after.
    float peekWanted = o.phase == Phase::cut ? tm.peek0 : (o.phase == Phase::open && o.tau < tm.peek2 ? tm.peek1 : 0);
    o.peek += (peekWanted - o.peek) * (1 - std::exp(-dt * 6));
    quat tiltRotation = quatEuler({tilt_.y * 0.14f * settings_.tilt + o.peek, tilt_.x * 0.22f * settings_.tilt, 0});
    quat facing = anchor.rotation * tiltRotation;

    float guideWanted = o.phase == Phase::ready ? 1 : (o.phase == Phase::cut ? 0.35f : 0);
    o.guide += (guideWanted - o.guide) * (1 - std::exp(-dt * 8));

    if (o.phase == Phase::zoom) {
        float k = ease::smooth(clamp01(o.t / 0.85f));
        o.position = mix(o.from, target, k);
        o.rotation = slerp(o.fromRotation, facing, k) * quat::axisAngle(std::sin(k * (float)M_PI) * 0.35f, {0, 1, 0});
        o.scale = lerp(o.scale, 1, k);
        if (o.t >= 0.85f) {
            o.phase = Phase::ready;
            o.t = 0;
            sweepStart_ = time_;
            show(hintFor(style));
        }
        opening_ = o;
        composePieces();
        return;
    }

    if (o.phase == Phase::exit && o.unopened) {
        float k = progress(o.t, o.exitT0, o.exitT0 + 0.75f);
        if (o.cut > 0) {
            float e = ease::inCubic(k);
            o.position = o.exitPosition - vec3(0, 3.4f * e, 0);
            o.rotation = o.exitRotation * quat::axisAngle(0.35f * e, {1, 0, 0}) * quat::axisAngle(0.12f * e, {0, 0, 1});
        } else {
            const PackPose& pose = poses_[o.pack];
            float e = ease::smooth(k);
            o.position = mix(o.exitPosition, pose.position, e);
            o.rotation = slerp(o.exitRotation, quatEuler(pose.euler), e) * quat::axisAngle(-std::sin(e * (float)M_PI) * 0.3f, {0, 1, 0});
            o.scale = lerp(o.exitScale, pose.scale, e);
        }
        opening_ = o;
        composePieces();
        if (k >= 1) finish(o.cut == 0);
        return;
    }

    if (o.phase != Phase::exit) {
        o.position = target;
        o.rotation = slerp(o.rotation, facing, 1 - std::exp(-dt * 10));
        o.scale = 1;
    }

    if (o.phase == Phase::ready || o.phase == Phase::cut) {
        if (o.phase == Phase::ready && settings_.autoOpen > 0 && o.t > settings_.autoOpen) o.phase = Phase::cut;
        if (o.phase == Phase::cut && !hintCleared_) { show(nullptr); hintCleared_ = true; }
        bool cutting = o.phase == Phase::cut;
        bool automatic = cutting && !o.manual;
        float before = o.cut;
        auto jerky = [&](float d) { return (dt / d) * (0.35f + 1.3f * std::max(0.f, std::sin(o.t * 21) + 0.55f * std::sin(o.t * 47 + 1))); };
        float flakeScale = 1, smoke = 0;
        switch (style) {
            case Opening::tear: case Opening::lid: case Opening::rip: {
                if (automatic) o.cut = std::min(1.f, o.cut + jerky(style == Opening::rip ? 0.6f : 0.75f));
                float delta = o.cut - before;
                o.jolt = std::min(1.f, o.jolt * std::exp(-dt * 18) + delta * 6);
                o.position.y += 0.004f * o.jolt;
                o.flakeAcc += delta * 26;
                break;
            }
            case Opening::roll: {
                if (automatic) o.cut = std::min(1.f, o.cut + (dt / 1.15f) * (0.6f + 0.6f * std::max(0.f, std::sin(o.t * 13))));
                float delta = o.cut - before;
                o.flakeAcc += delta * 16;
                if (delta > 0) o.position.y += 0.0012f * std::sin(o.t * 60);
                break;
            }
            case Opening::zip: {
                if (automatic) o.cut = std::min(1.f, o.cut + dt / 1.05f);
                float delta = o.cut - before;
                o.flakeAcc += delta * 40;
                flakeScale = 0.8f;
                if (delta > 0) o.position.y += 0.0015f * std::sin(o.t * 95);
                break;
            }
            case Opening::melt: {
                if (automatic) o.cut = std::min(1.f, o.cut + dt / 1.15f);
                float delta = o.cut - before;
                o.flakeAcc += delta * 9;
                flakeScale = 0.7f;
                if (delta > 0) smoke = dt * 22;
                break;
            }
        }
        opening_ = o;
        composePieces();
        shedFlakes(flakeScale);
        if (smoke > 0) {
            opening_.smokeAcc += smoke * std::max(0.f, settings_.particles);
            while (opening_.smokeAcc > 1) {
                opening_.smokeAcc -= 1;
                particles_.puff(cutTips()[0] + vec3(0, 0.02f, 0.03f));
            }
            if (frand() < 0.5f) particles_.spawnSparks(cutTips()[0], 1, {0.01f, 0.01f, 0.01f}, 1.2f, 0.5f);
        }
        if (o.cut >= 1) {
            opening_.phase = Phase::open;
            opening_.tau = 0;
            opening_.cut = 1;
            int n = style == Opening::melt ? 0 : (style == Opening::rip ? 14 : 12);
            for (int k = 0; k < n; ++k) {
                std::vector<vec3> tips = cutTips(0.55f + frand() * 0.45f);
                int c = particles_.count(1, settings_.particles);
                for (int j = 0; j < c; ++j) particles_.flake(tips[k % tips.size()]);
            }
        }
        return;
    }

    o.tau += dt;
    float tau = o.tau;
    if (o.phase == Phase::open && tau > tm.present) {
        o.phase = Phase::present;
        char text[64]; snprintf(text, sizeof text, "1 / %d · tap for the next card", dealtCount_);
        show(text);
    }
    bool premium = o.rare && o.premAt > 0 && tau >= o.premAt && o.phase != Phase::exit;
    if (o.rare && o.phase == Phase::present && o.premAt > 0 && o.revealAt == 0 && tau > o.premAt + 5) {
        opening_ = o;
        reveal();
        o = opening_;
    }
    float auraWanted = premium ? (o.phase == Phase::fan ? 0.45f : (o.revealAt > 0 ? 1.f : 0.7f)) : 0.f;
    o.aura += (auraWanted - o.aura) * (1 - std::exp(-dt * 4));
    opening_ = o;
    composePieces();
    o = opening_;
    if (style == Opening::melt && o.phase == Phase::open) {
        if (tau < 0.7f) {
            o.smokeAcc += dt * 10 * std::max(0.f, settings_.particles);
            while (o.smokeAcc > 1) {
                o.smokeAcc -= 1;
                particles_.puff(cutTips(frand())[0] + vec3(0, 0.02f, 0.03f));
            }
        }
        if (openingPose_.stripVisible && openingPose_.strip.dissolve > 0 && frand() < 0.8f) {
            vec4 local((frand() - 0.5f) * pouch::width, stripMid + (frand() - 0.5f) * (1 - tearLine) * pouch::height, 0.02f, 1);
            vec4 w = openingPose_.stripModel * local;
            particles_.spawnSparks(w.xyz(), 2, vec3(0), 1.6f, 0.35f);
        }
    }
    if (premium && frand() < 0.7f && !openingPose_.cards.empty()) {
        int last = (int)openingPose_.cards.size() - 1;
        vec3 p = cardWorld(last, {(frand() - 0.5f) * cardWidth * 1.2f, -cardHeight() * 0.45f, 0.02f});
        particles_.spawnSparks(p, particles_.count(1, settings_.particles), {0.02f, 0.02f, 0.02f}, 2.2f, 0.35f, true);
    }
    if (o.rare && o.revealAt > 0 && !o.burst && tau >= o.revealAt + 0.42f && !openingPose_.cards.empty()) {
        o.burst = true;
        sweepStart_ = time_;
        burstTime_ = clock_;
        vec3 centre = cardWorld((int)openingPose_.cards.size() - 1);
        particles_.spawnSparks(centre, particles_.count(160, settings_.particles), {0.3f, 0.4f, 0.05f}, 2.6f, 0.5f, true);
        int n = particles_.count(90, settings_.particles);
        for (int k = 0; k < n; ++k) {
            particles_.spawnFlake(centre + vec3((frand() - 0.5f) * 0.3f, (frand() - 0.5f) * 0.4f, 0.05f),
                                  vec3((frand() - 0.5f) * 3, 0.8f + frand() * 2.2f, 0.3f + frand() * 1.2f),
                                  0.015f + frand() * 0.03f, StageParticles::burstFlakes[k % 4], 1.6f + frand());
        }
    }
    if (o.phase == Phase::exit) {
        float k = ease::inCubic(progress(tau, o.exitAt, o.exitAt + 0.5f));
        exitDrop_ = 3.2f * k;
        if (tau > o.exitAt + 0.78f) {
            opening_ = o;
            finish(false);
            return;
        }
    }
    opening_ = o;
    composePieces();
}

} // namespace ck
