// The stage scene: the carousel of packs, the gestures, and the opening
// choreography, a port of StageScene / StageGestures / StageOpening /
// StagePieces / StageCards. The renderer reads `poses`, `openingPose`
// and `particles` after `advance()`.
#pragma once
#include <string>
#include <vector>
#include <optional>
#include <functional>
#include "stage_math.h"
#include "stage_settings.h"
#include "stage_particles.h"

namespace ck {

enum class Phase : int { idle = 0, zoom, ready, cut, open, present, fan, exit };

struct PackPose {
    mat4 model;
    vec3 position, euler;
    float scale = 1;
    bool visible = true;
    mat4 shadowModel;
    float shadowOpacity = 0;
};

struct CardPose {
    float x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0, s = 1;
    static CardPose mix(const CardPose& a, const CardPose& b, float t) {
        return {lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t), lerp(a.rx, b.rx, t), lerp(a.ry, b.ry, t), lerp(a.rz, b.rz, t), lerp(a.s, b.s, t)};
    }
    mat4 model() const { return ck::model({x, y, z}, {rx, ry, rz}, s); }
};

/// The dials of one piece of the pack being opened, for the shader.
struct PieceDials {
    float tearV = 2, tearSide = 0, cutP = 0, inside = 0;
    float lineMode = 0, cutDir = 0, perf = 0, heat = 0;
    float tipGlow = 0, dissolve = 0, innerGlow = 0, guide = 0;
    float peel = 0, peelDir = 1, peelAmt = 1, fly = 0;
    float mouth = 0, mouthK = 1;
};

struct OpeningPose {
    struct CardDraw { mat4 model; int order = 0; float emissive = 0; };
    bool visible = false;
    bool bodyVisible = false; mat4 bodyModel; PieceDials body;
    bool stripVisible = false; mat4 stripModel; PieceDials strip;
    bool tabVisible = false; mat4 tabModel;
    std::vector<CardDraw> cards;
    float auraOpacity = 0, auraPulse = 0, raysOpacity = 0, dimOpacity = 0;
    bool premium = false;
};

struct OpeningState {
    struct Card { float dealtAt = -1, direction = 1; };
    Phase phase = Phase::idle;
    Opening style = Opening::tear;
    int pack = 0;
    float t = 0, tau = 0, cut = 0;
    bool manual = false;
    int top = 0;
    float jolt = 0, flakeAcc = 0, smokeAcc = 0, fanAt = 0, peek = 0, premAt = 0, revealAt = 0;
    bool burst = false;
    float aura = 0, low = 1;
    bool rare = true;
    int openings = 0;
    Card cards[5];
    vec3 from; quat fromRotation; float fromScale = 1;
    vec3 position; quat rotation; float scale = 1;
    Phase exitFrom = Phase::idle;
    float exitAt = 0, exitT0 = 0;
    bool unopened = false;
    vec3 exitPosition; quat exitRotation; float exitScale = 1;
    float guide = 0;
};

struct StageCamera {
    vec3 position{0, 0.26f, 6.4f}, target{0, -0.2f, -0.4f};
    float fovY = 28 * (float)M_PI / 180, aspect = 1;
    mat4 view, projection;
    mat4 viewProjection() const { return projection * view; }
};

class StageScene {
public:
    struct Pack { int index = 0; float pop = 1, spinYaw = 0, spinVelocity = 0, spinTarget = 0, spinPitch = 0, spinPitchVelocity = 0; };

    explicit StageScene(const StageSettings& s);
    void setSettings(const StageSettings& s);
    const StageSettings& settings() const { return settings_; }

    // Inputs (view points).
    void resize(float width, float height);
    void setDeviceTilt(float x, float y);
    void pointerMoved(bool active, float x, float y);
    void dragBegan(float x, float y, double now);
    void dragChanged(float x, float y, double now);
    void dragEnded(float x, float y, double now);
    void bringToFront(int index);
    /// Opens the front pack with `cardCount` cards (the pictures live in the renderer).
    bool open(int index, int cardCount);
    void exit();

    void advance(float dt);

    // Outputs.
    const std::vector<PackPose>& poses() const { return poses_; }
    const std::vector<Pack>& packs() const { return packs_; }
    const StageCamera& camera() const { return camera_; }
    vec2 viewport() const { return viewport_; }
    float time() const { return time_; }
    float sweep() const { return sweep_; }
    Phase phase() const { return opening_.phase; }
    int frontIndex() const { return (int)wrapf(roundf_(target_), (float)packs_.size()); }
    int openingPack() const { return opening_.pack; }
    const OpeningPose& openingPose() const { return openingPose_; }
    const StageParticles& particles() const { return particles_; }
    float raysLevel() const { return raysLevel_; }
    float dimLevel() const { return dimLevel_; }
    double burstTime() const { return burstTime_; }
    double clock() const { return clock_; }
    float floorLine() const;
    int dealtCount() const { return dealtCount_; }
    float cardAspect = 0.716f;
    float cardHeight() const { return cardWidth / cardAspect; }
    static constexpr float cardWidth = 0.8f;

    /// Set by the host: the front pack was tapped and needs its cards (return false to leave it sealed).
    std::function<bool(int)> onOpenRequest;
    std::function<void(Phase)> onPhase;
    std::function<void(const std::string&)> onHint;

    static constexpr float tearLine = pouch::tearLine;
    static constexpr float lineY = (tearLine - 0.5f) * pouch::height;
    static constexpr float stripMid = (tearLine - 0.5f) * pouch::height + ((1 - tearLine) * pouch::height) / 2;

private:
    struct Drag { vec2 start, last; double startTime = 0, lastTime = 0; float moved = 0, speed = 0; int spinning = -1; };
    struct Anchor { vec3 position; quat rotation; float distance = 0, halfWidth = 0; };
    struct StyleTiming { float present, reveal, peek0, peek1, peek2; };
    struct PieceMotion {
        vec3 bodyPosition, bodyRotation; bool bodyVisible = true;
        vec3 stripPosition{0, stripMid, 0}, stripRotation; bool stripVisible = true;
        float mouth = 0, dissolve = 0, fly = 0, heat = 0, tipGlow = 0, innerGlow = 0;
    };

    static StyleTiming timing(Opening s);
    static const char* hintFor(Opening s);
    void layoutCamera();
    void rebuildPacks(bool popping);
    void settleSpins(float dt);
    void placePacks(float dt);
    void ray(float x, float y, vec3& origin, vec3& direction) const;
    int packAt(float x, float y) const;

    // Opening.
    quat cameraRotation() const;
    Anchor anchorBase() const;
    float halfTan() const { return std::tan(camera_.fovY / 2); }
    void advanceOpening(float direction);
    void cutByHand(float dx);
    void dealNext(float direction);
    void reveal();
    void finish(bool reappear);
    void show(const char* text);
    void stepOpening(float rawDt);
    vec3 cutPoint(float x, float lift = 0.03f) const;
    std::vector<vec3> cutTips(float cut) const;
    std::vector<vec3> cutTips() const { return cutTips(opening_.cut); }
    void shedFlakes(float scale = 1);
    vec3 cardWorld(int index, vec3 offset = vec3(0)) const;
    PieceMotion pieceMotion() const;
    void composePieces();
    // Cards.
    CardPose restPose(int i) const;
    CardPose tearPose(int i, float tau) const;
    CardPose stylePose(int i, float tau) const;
    CardPose fanPose(int i) const;
    CardPose rarePose(CardPose pose, float tau) const;
    CardPose cardPose(int i, Phase phase, float tau) const;
    int drawOrder(int i, Phase phase, float z) const;
    std::vector<OpeningPose::CardDraw> cardDraws(const mat4& anchor, bool showInside) const;

    StageSettings settings_;
    std::vector<Pack> packs_;
    std::vector<PackPose> poses_;
    StageCamera camera_;
    vec2 viewport_{1, 1};
    float time_ = 0, sweep_ = 9, sweepStart_ = 0.8f;
    Phase lastPhase_ = Phase::idle;
    OpeningState opening_;
    OpeningPose openingPose_;
    float exitDrop_ = 0, raysLevel_ = 0, dimLevel_ = 0;
    StageParticles particles_;
    double burstTime_ = -1;
    int dealtCount_ = 0;
    float angle_ = 0, velocity_ = 0, target_ = 0, radius_ = 2, away_ = 0;
    vec2 pointer_, deviceTilt_, tilt_;
    bool pointerActive_ = false;
    std::optional<Drag> drag_;
    double clock_ = 0;
    bool hintCleared_ = false;
};

} // namespace ck
