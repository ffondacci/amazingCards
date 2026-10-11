// Where the five cards of an opened pack are, frame by frame. A port of
// StageCards.swift; every pose is in the opened pack's frame.
#include "stage_scene.h"

namespace ck {

CardPose StageScene::restPose(int i) const {
    CardPose p; p.y = -0.1f; p.z = (float)(2 - i) * 0.0012f; return p;
}

CardPose StageScene::tearPose(int i, float tau) const {
    float behind = (float)(i - opening_.top);
    float rise = ease::outCubic(progress(tau, 0.25f, 1));
    float settle = ease::smooth(progress(tau, 1.45f, 2.1f));
    CardPose p;
    p.y = lerp(lerp(-0.1f, 0.5f, rise), 0, settle) - std::max(0.f, behind) * 0.012f * settle;
    p.z = (float)(2 - i) * 0.0012f * (1 - settle) + settle * (0.34f - std::max(0.f, behind) * 0.006f);
    p.s = lerp(1, 1.3f, settle);
    p.rz = settle * (behind > 0 ? ((float)((i * 7919) % 11) / 11 - 0.5f) * 0.05f : 0);
    return p;
}

CardPose StageScene::stylePose(int i, float tau) const {
    CardPose rest = restPose(i);
    CardPose front = tearPose(i, 99);
    auto p = progress;
    const float pi = (float)M_PI;
    CardPose out; out.y = 0.5f; out.z = (float)(2 - i) * 0.0012f;
    switch (opening_.style) {
        case Opening::rip: {
            float k = p(tau, 0.2f, 1);
            CardPose bounce = rest;
            bounce.y = k > 0 ? 0.5f - 0.6f * std::exp(-4 * k) * std::cos(9 * k) : rest.y;
            return CardPose::mix(bounce, front, ease::smooth(p(tau, 1.5f, 2.05f)));
        }
        case Opening::zip: {
            float tilt = ease::smooth(p(tau, 0.45f, 0.95f));
            float angle = -1.95f * tilt, ox = -0.5f * tilt, oy = 0.12f * tilt;
            float start = 0.9f + (float)(4 - i) * 0.16f;
            float slide = p(tau, start, start + 0.34f);
            float along = lerp(-0.1f, 1.4f, slide * slide);
            CardPose slid; slid.x = ox - along * std::sin(angle); slid.y = oy + along * std::cos(angle); slid.z = (float)(2 - i) * 0.0012f; slid.rz = angle;
            float gather = p(tau, start + 0.3f, start + 0.72f);
            bool portrait = viewport_.x < viewport_.y;
            CardPose pile; pile.x = (portrait ? 0.03f : 0.2f) + 0.03f * (float)(2 - i); pile.y = -0.12f; pile.z = 0.32f + (float)(4 - i) * 0.008f; pile.rz = 0.05f * (float)(2 - i); pile.s = 1.05f;
            CardPose mixed = CardPose::mix(slid, pile, ease::outCubic(gather));
            mixed.z = lerp(slid.z, pile.z, smoothstep(0, 0.3f, gather));
            mixed.y -= 0.12f * std::sin(pi * gather);
            return CardPose::mix(mixed, front, ease::smooth(p(tau, 2.35f, 2.8f)));
        }
        case Opening::melt: {
            CardPose floating = CardPose::mix(rest, out, ease::smooth(p(tau, 0.3f, 1.5f)));
            float wave = std::sin(pi * p(tau, 1.55f, 2.45f));
            Anchor anchor = anchorBase();
            float room = std::min(1.f, std::max(0.5f, (2 * (anchor.distance - 0.22f) * anchor.halfWidth) / 1.9f));
            floating.x += 0.13f * (float)(i - 2) * wave * room;
            floating.y += 0.06f * std::sin(tau * 2.1f + (float)i) * wave;
            floating.z += 0.05f * (float)(4 - i) * wave;
            floating.rz += 0.07f * (float)(2 - i) * wave;
            floating.ry = 0.28f * std::sin(tau * 1.6f + (float)i * 1.3f) * wave;
            return CardPose::mix(floating, front, ease::smooth(p(tau, 2.2f, 2.7f)));
        }
        case Opening::roll: {
            CardPose rising = CardPose::mix(rest, out, ease::outCubic(p(tau, 0.3f, 0.95f)));
            Anchor anchor = anchorBase();
            float room = std::min(1.f, std::max(0.5f, (2 * (anchor.distance - 0.22f) * anchor.halfWidth) / 1.9f));
            float spread = (float)(2 - i) * 0.19f;
            CardPose arc; arc.x = std::sin(spread) * 1.05f * room; arc.y = (-0.62f + std::cos(spread) * 1.05f) * room; arc.z = 0.22f + (float)(4 - i) * 0.006f; arc.rz = -spread; arc.s = room;
            rising = CardPose::mix(rising, arc, ease::smooth(p(tau, 1.35f, 1.9f)));
            return CardPose::mix(rising, front, ease::smooth(p(tau, 2.35f, 2.9f)));
        }
        case Opening::lid: case Opening::tear: default: {
            float drop = -0.55f * ease::smooth(p(tau, 0.15f, 0.6f));
            float start = 0.62f + (float)(4 - i) * 0.15f;
            CardPose lifted = rest;
            lifted.y = lerp(rest.y + drop, 0.86f, ease::outCubic(p(tau, start, start + 0.32f)));
            float swing = p(tau, start + 0.3f, start + 0.78f);
            CardPose pose = CardPose::mix(lifted, front, ease::smooth(swing));
            pose.z += 0.25f * std::sin(pi * swing);
            pose.rx += 0.55f * std::sin(pi * swing);
            return pose;
        }
    }
}

CardPose StageScene::fanPose(int i) const {
    float aspect = viewport_.x / viewport_.y;
    Anchor anchor = anchorBase();
    float room = (anchor.distance - 0.34f) * anchor.halfWidth;
    float gap = aspect < 1 ? 0.34f : 0.72f;
    float sc = std::min(0.82f, ((aspect < 1 ? 1.62f : 1.84f) * room) / ((4 * gap + 1) * cardWidth));
    float k = (float)(i - 2);
    CardPose p; p.x = k * cardWidth * sc * gap; p.y = -0.05f - 0.03f * k * k * sc; p.z = 0.34f + (float)i * 0.004f; p.rz = -k * 0.08f; p.s = sc;
    return p;
}

CardPose StageScene::rarePose(CardPose pose, float tau) const {
    CardPose p = pose;
    float prem = opening_.premAt, reveal = opening_.revealAt;
    const float pi = (float)M_PI;
    if (reveal == 0 || tau < reveal) {
        p.ry += pi;
        if (prem > 0 && tau >= prem) {
            float since = tau - prem;
            float w = ease::outCubic(progress(since, 0, 0.45f));
            float v = w * std::min(1.f, 0.35f + since * 0.3f);
            p.z += 0.1f * w;
            p.s *= 1 + 0.05f * w;
            p.x += 0.007f * v * std::sin(since * 57);
            p.y += 0.005f * v * std::sin(since * 43 + 1);
            p.rz += 0.014f * v * std::sin(since * 31);
        }
        return p;
    }
    float since = tau - reveal;
    float turn = progress(since, 0, 0.9f);
    p.ry += pi * (1 - ease::smooth(turn));
    p.z += 0.1f + 0.14f * std::sin(pi * turn);
    p.s *= 1.05f + 0.1f * std::sin(pi * turn);
    float settle = smoothstep(0.8f, 1.6f, since);
    p.ry += settle * 0.22f * std::sin((since - 0.8f) * 1.1f);
    p.rx += settle * 0.07f * std::sin((since - 0.8f) * 1.5f);
    p.y += settle * 0.015f * std::sin(since * 1.7f);
    return p;
}

CardPose StageScene::cardPose(int i, Phase phase, float tau) const {
    StyleTiming tm = timing(opening_.style);
    CardPose pose = opening_.style == Opening::tear ? tearPose(i, tau) : (tau < tm.present ? stylePose(i, tau) : tearPose(i, 99));
    int last = dealtCount_ - 1;
    if (i == last && opening_.rare) pose = rarePose(pose, tau);
    const OpeningState::Card& card = opening_.cards[i];
    bool fanning = phase == Phase::fan;
    if (card.dealtAt >= 0 && card.dealtAt <= tau) {
        float k = progress(tau, card.dealtAt, card.dealtAt + 0.5f);
        float dir = card.direction;
        CardPose flung;
        flung.x = pose.x + dir * 3.2f * ease::inCubic(k) + dir * 0.2f * k;
        flung.y = pose.y + 0.35f * k;
        flung.z = pose.z + 0.3f * ease::outCubic(k * 2);
        flung.rx = 0; flung.ry = dir * 0.8f * k; flung.rz = -dir * 0.55f * k; flung.s = pose.s;
        pose = flung;
        if (fanning) {
            float w = ease::outCubic(progress(tau, opening_.fanAt + (float)i * 0.06f, opening_.fanAt + (float)i * 0.06f + 0.65f));
            CardPose parked; parked.x = dir * 3.4f; parked.y = pose.y; parked.z = pose.z; parked.ry = dir * 0.8f; parked.rz = -dir * 0.55f; parked.s = pose.s;
            pose = CardPose::mix(k < 1 ? flung : parked, fanPose(i), w);
        }
    } else if (fanning) {
        pose = CardPose::mix(pose, fanPose(i), ease::smooth(progress(tau, opening_.fanAt, opening_.fanAt + 0.6f)));
        if (i == last) {
            pose.ry += 0.12f * std::sin(tau * 1.3f);
            pose.y += 0.03f * progress(tau, opening_.fanAt, opening_.fanAt + 0.6f);
        }
    }
    return pose;
}

int StageScene::drawOrder(int i, Phase phase, float z) const {
    int base = phase == Phase::fan ? 20 + i : (opening_.cards[i].dealtAt >= 0 ? 40 + i : 30 - i);
    return 100 + base + (int)(30 * std::min(1.3f, std::max(-1.3f, z)));
}

std::vector<OpeningPose::CardDraw> StageScene::cardDraws(const mat4& anchor, bool showInside) const {
    const OpeningState& o = opening_;
    int count = dealtCount_;
    std::vector<OpeningPose::CardDraw> draws;
    if (count <= 0 || !showInside) return draws;
    bool exiting = o.phase == Phase::exit;
    Phase phase = exiting ? o.exitFrom : o.phase;
    float tau = exiting ? o.exitAt : o.tau;
    bool night = settings_.lighting == Lighting::night;
    float glow = night ? 0.32f : 0;
    const float pi = (float)M_PI;
    if (o.style == Opening::melt) glow += 0.3f * std::sin(pi * progress(tau, 0.3f, 2.7f));
    for (int i = 0; i < count; ++i) {
        bool visible = o.style == Opening::tear ? tau > 0.28f : true;
        if (!visible) continue;
        CardPose pose = (o.phase == Phase::cut || o.phase == Phase::ready) ? restPose(i) : cardPose(i, phase, tau);
        if (exiting) {
            float delay = (float)(o.cards[i].dealtAt < 0 ? std::max(0, i - o.top) : i) * 0.05f;
            float k = progress(o.tau, o.exitAt + delay, o.exitAt + delay + 0.6f);
            float side = i % 2 == 1 ? 1.f : -1.f;
            pose.y += 0.12f * std::sin(pi * std::min(1.f, k * 2.2f)) - 3.2f * ease::inCubic(k);
            pose.x += side * 0.25f * k;
            pose.rz += side * 0.5f * ease::inCubic(k);
            pose.rx += 0.5f * ease::inCubic(k);
            pose.s *= 1 - 0.3f * k;
        }
        OpeningPose::CardDraw d; d.model = anchor * pose.model(); d.order = drawOrder(i, phase, pose.z); d.emissive = glow;
        draws.push_back(d);
    }
    return draws;
}

} // namespace ck
