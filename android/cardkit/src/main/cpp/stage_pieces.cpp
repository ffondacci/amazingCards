// Where the body and the strip of the opened pack are, what their shaders
// are told, and where the foil is being cut. A port of StagePieces.swift.
#include "stage_scene.h"

namespace ck {

vec3 StageScene::cutPoint(float x, float lift) const {
    vec4 local((x - 0.5f) * pouch::width * 0.95f, lineY, lift, 1);
    return (openingPose_.bodyModel * local).xyz();
}

std::vector<vec3> StageScene::cutTips(float c) const {
    switch (opening_.style) {
        case Opening::zip: return {cutPoint(1 - c)};
        case Opening::rip: return {cutPoint(0.5f - c / 2), cutPoint(0.5f + c / 2)};
        default: return {cutPoint(c)};
    }
}

void StageScene::shedFlakes(float scale) {
    std::vector<vec3> tips = cutTips();
    int i = 0;
    while (opening_.flakeAcc > 1) {
        opening_.flakeAcc -= 1;
        int n = particles_.count(1, settings_.particles);
        for (int k = 0; k < n; ++k) particles_.flake(tips[i % tips.size()], scale);
        i += 1;
    }
}

vec3 StageScene::cardWorld(int index, vec3 offset) const {
    if (index >= (int)openingPose_.cards.size()) return opening_.position;
    return (openingPose_.cards[index].model * vec4(offset, 1)).xyz();
}

StageScene::PieceMotion StageScene::pieceMotion() const {
    PieceMotion m;
    const OpeningState& o = opening_;
    Opening style = o.style;
    bool apart = o.phase == Phase::open || o.phase == Phase::present || o.phase == Phase::fan || (o.phase == Phase::exit && !o.unopened);
    if (!apart) {
        m.heat = style == Opening::melt && o.phase == Phase::cut ? 1 : 0;
        m.tipGlow = style == Opening::melt && o.phase == Phase::cut && o.cut > 0 ? 1 : 0;
        return m;
    }
    float tau = o.tau;
    auto p = progress;
    const float pi = (float)M_PI;
    switch (style) {
        case Opening::tear: {
            float s = p(tau, 0, 0.9f);
            m.stripPosition = {3 * s * s, stripMid + 0.5f * ease::outCubic(s) - 2.6f * s * s * s, 0.3f * s};
            m.stripRotation = {-0.6f * s, 0.5f * s, -1.2f * s * s};
            m.stripVisible = s < 1;
            m.mouth = ease::outCubic(p(tau, 0, 0.35f));
            float d = ease::inCubic(p(tau, 1, 1.6f));
            m.bodyPosition = {0, -0.025f * std::sin(pi * p(tau, 0, 0.3f)) - 3.2f * d, -0.2f * d};
            m.bodyRotation = {0.25f * d, 0, 0.06f * d};
            m.bodyVisible = d < 1;
            break;
        }
        case Opening::rip: {
            m.fly = p(tau, 0, 0.9f);
            m.stripVisible = m.fly < 1;
            m.mouth = ease::outCubic(p(tau, 0, 0.35f));
            float d = ease::inCubic(p(tau, 0.95f, 1.55f));
            m.bodyPosition = {0, -0.03f * std::sin(pi * p(tau, 0, 0.3f)) - 3.2f * d, -0.2f * d};
            m.bodyRotation = {0.25f * d, 0, -0.05f * d};
            m.bodyVisible = d < 1;
            break;
        }
        case Opening::zip: {
            float s = p(tau, 0.12f, 0.95f);
            m.stripPosition = {0, stripMid - 2.9f * s * s, -0.3f * ease::outCubic(s)};
            m.stripRotation = {-0.7f * s, 0, 0.15f * s};
            m.stripVisible = s < 1;
            m.mouth = ease::outCubic(p(tau, 0.1f, 0.45f));
            float tilt = ease::smooth(p(tau, 0.45f, 0.95f));
            float d = ease::inCubic(p(tau, 1.95f, 2.45f));
            m.bodyRotation = {0, 0, -1.95f * tilt - 0.4f * d};
            m.bodyPosition = {-0.5f * tilt - 0.4f * d, 0.12f * tilt - 3.2f * d, -0.2f * d};
            m.bodyVisible = d < 1;
            break;
        }
        case Opening::melt: {
            m.stripPosition = {0.04f * std::sin(tau * 1.4f), stripMid + 0.13f * ease::outCubic(p(tau, 0, 1.2f)), 0.08f * tau};
            m.stripRotation = {0.1f * std::sin(tau * 1.1f), 0, 0.07f * std::sin(tau * 1.7f)};
            m.dissolve = p(tau, 0.1f, 1.1f);
            m.stripVisible = m.dissolve < 1;
            m.heat = 1 - p(tau, 0, 1.3f);
            m.mouth = ease::outCubic(p(tau, 0, 0.45f));
            float d = ease::inCubic(p(tau, 1, 1.75f));
            m.bodyPosition = {0, -3.2f * d, -0.2f * d};
            m.bodyRotation = {0.2f * d, 0, 0};
            m.bodyVisible = d < 1;
            break;
        }
        case Opening::roll: {
            float s = p(tau, 0.08f, 0.9f);
            m.stripPosition = {0.12f * s + 1.5f * s * s, stripMid + 0.35f * ease::outCubic(s) - 2.5f * s * s * s, 0.25f * s};
            m.stripRotation = {0.4f * s, 0, -1.3f * s * s};
            m.stripVisible = s < 1;
            m.mouth = ease::outCubic(p(tau, 0, 0.35f));
            float d = ease::inCubic(p(tau, 0.95f, 1.45f));
            m.bodyPosition = {0, -3.2f * d, -0.2f * d};
            m.bodyRotation = {0.25f * d, 0, 0.05f * d};
            m.bodyVisible = d < 1;
            break;
        }
        case Opening::lid: {
            float drop = -0.55f * ease::smooth(p(tau, 0.15f, 0.6f));
            float d = ease::inCubic(p(tau, 1.55f, 2.05f));
            m.bodyPosition = {0, drop - 3.2f * d, -0.2f * d};
            m.bodyRotation = {0.25f * d, 0, 0};
            m.bodyVisible = d < 1;
            float away = p(tau, 0.6f, 1.25f);
            float angle = -(2.1f * ease::outCubic(p(tau, 0, 0.5f)) + 0.9f * away);
            float hinge = lineY + drop;
            float arm = stripMid - lineY;
            m.stripPosition = {0, hinge + arm * std::cos(angle) - 0.03f * std::sin(angle) - 2.6f * away * away, -0.03f + arm * std::sin(angle) + 0.03f * std::cos(angle) - 0.35f * away};
            m.stripRotation = {angle, 0, 0};
            m.stripVisible = away < 1;
            m.mouth = ease::outCubic(p(tau, 0, 0.4f));
            m.innerGlow = 0.22f * ease::outCubic(p(tau, 0, 0.3f)) * (1 - p(tau, 0.8f, 1.6f));
            break;
        }
    }
    if (o.phase == Phase::exit) m.bodyPosition.y -= exitDrop_;
    return m;
}

void StageScene::composePieces() {
    const OpeningState& o = opening_;
    PieceMotion motion = pieceMotion();
    Opening style = o.style;
    OpeningPose pose;
    pose.visible = true;
    mat4 anchor = translation(o.position) * o.rotation.matrix() * scale(vec3(o.scale));

    PieceDials body;
    body.tearV = tearLine;
    body.cutP = o.cut;
    body.inside = 1;
    body.lineMode = style == Opening::melt ? 2 : (style == Opening::zip ? 3 : 0);
    body.cutDir = style == Opening::zip ? 1 : (style == Opening::rip ? 2 : 0);
    body.perf = style == Opening::zip ? 1 : 0;
    body.heat = motion.heat;
    body.tipGlow = motion.tipGlow;
    body.innerGlow = motion.innerGlow;
    body.guide = o.guide;
    body.mouth = motion.mouth;
    body.mouthK = 1;
    PieceDials strip = body;
    strip.tearSide = 1;
    strip.peel = style == Opening::roll ? 2 : (style == Opening::rip ? 3 : 1);
    strip.peelDir = style == Opening::zip ? -1 : 1;
    strip.peelAmt = style == Opening::melt ? 0.5f : (style == Opening::lid ? 0.35f : 1);
    strip.dissolve = motion.dissolve;
    strip.fly = motion.fly;
    strip.guide = 0;
    strip.innerGlow = 0;

    pose.body = body;
    pose.strip = strip;
    pose.bodyVisible = motion.bodyVisible;
    pose.bodyModel = anchor * translation(motion.bodyPosition) * rotationYXZ(motion.bodyRotation.x, motion.bodyRotation.y, motion.bodyRotation.z);
    pose.stripVisible = motion.stripVisible && o.phase != Phase::zoom;
    pose.stripModel = anchor * translation(motion.stripPosition)
        * rotationYXZ(motion.stripRotation.x, motion.stripRotation.y, motion.stripRotation.z)
        * translation({0, -stripMid, 0});
    // Before the cut the strip is part of the body: one pass draws both sides of the line.
    if (o.phase == Phase::zoom || o.phase == Phase::ready || (o.phase == Phase::cut && o.cut <= 0.001f)) {
        pose.stripVisible = false;
        pose.body.tearSide = 0;
        pose.body.tearV = o.phase == Phase::zoom ? 2 : tearLine;
        if (o.phase != Phase::zoom) { pose.strip = strip; pose.stripVisible = true; }
    }
    if (style == Opening::zip && pose.stripVisible) {
        float x = (0.5f - o.cut) * pouch::width + 0.02f;
        pose.tabVisible = true;
        pose.tabModel = pose.stripModel * translation({x, lineY, 0.07f}) * rotationY(0.35f);
    }
    bool showInside = o.phase == Phase::cut || o.phase == Phase::open || o.phase == Phase::present || o.phase == Phase::fan || o.phase == Phase::exit;
    pose.cards = cardDraws(anchor, showInside);
    pose.auraOpacity = o.aura;
    pose.auraPulse = o.revealAt > 0 ? std::exp(-std::pow(o.tau - o.revealAt - 0.45f, 2.f) / 0.04f) : 0;
    bool dealing = o.phase == Phase::open || o.phase == Phase::present || o.phase == Phase::fan;
    pose.premium = o.rare && o.premAt > 0 && o.tau >= o.premAt && o.phase != Phase::exit;
    pose.raysOpacity = settings_.rays && dealing && o.tau > timing(style).reveal ? 1 : 0;
    pose.dimOpacity = pose.premium ? 1 : 0;
    openingPose_ = pose;
}

} // namespace ck
