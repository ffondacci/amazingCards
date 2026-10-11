// Draws a StageScene with Vulkan: background, packs, their reflection and
// shadow, the pack being opened, its cards and the particles. A port of
// StageRenderer.swift with the same passes and the same uniforms.
#pragma once
#include <vulkan/vulkan.h>
#include <map>
#include <memory>
#include <future>
#include <string>
#include <vector>
#include "vk_context.h"
#include "stage_scene.h"
#include "pouch_geometry.h"

namespace ck {

/// RGBA8 pixels, top row first, premultiplied.
struct Pixels {
    uint32_t width = 0, height = 0;
    std::vector<uint8_t> rgba;
    bool empty() const { return width == 0 || height == 0 || rgba.empty(); }
};

/// Pictures printed on one pack (PackSkin): front, back (defaults to the front), masks.
struct SkinPixels {
    std::string id;
    Pixels front, back, frontMask, backMask;
};

/// Pictures of one card (CardSkin).
struct CardPixels {
    std::string id;
    Pixels front, back, mask;
};

class StageRenderer {
public:
    StageRenderer(VkContext& context, StageScene& scene);
    ~StageRenderer();
    bool init();
    void destroy();

    void setSkin(int index, const SkinPixels* skin);
    /// The cards of the next deal, uploaded ahead of the tap.
    void prepareCards(std::vector<CardPixels> cards);
    int preparedCount() const { return (int)prepared_.size(); }
    /// Called when the scene opens a pack: the prepared cards become the dealt ones.
    void dealPrepared();
    void render();

private:
    struct Mesh { VkBuffer_ vertices, indices; uint32_t count = 0; };
    struct Material { VkDescriptorSet set = VK_NULL_HANDLE; };
    struct Skin { std::string id; VkTexture front, back, frontMask, backMask; };
    struct CardTextures { std::string id; VkTexture front, back, mask; bool ownsMask = true; };
    struct Retired { VkTexture texture; uint64_t frame; };
    struct FrameResources {
        VkBuffer_ frameUBO, objectUBO, flakes, sprites;
        VkDescriptorSet set0 = VK_NULL_HANDLE;
        uint32_t objectCursor = 0;
        bool wrinklesBound = false;
    };
    enum class Blend { none, alpha, premultiplied, additive };
    enum class Depth { write, read, none };

    VkPipeline pipeline(const char* vert, const char* frag, Blend blend, bool coverage, VkCullModeFlags cull, Depth depth, bool vertexInput);
    bool createLayouts();
    bool createPipelines();
    bool createFrames();
    void buildRays();
    VkTexture solid(uint8_t r, uint8_t g, uint8_t b, uint8_t a, bool srgb);
    VkTexture texture(const Pixels& p, bool srgb);
    Mesh upload(const PouchMesh& mesh);
    void destroyMesh(Mesh& m);
    void retire(VkTexture& t);
    void sweepRetired();
    VkDescriptorSet material(const VkTexture& art, const VkTexture& mask);
    void rebuildAssetsIfNeeded();
    void bindWrinkles(FrameResources& f);

    // Drawing.
    uint32_t pushObject(FrameResources& f, const struct ObjectUniforms& o);
    void bindObject(VkCommandBuffer cmd, FrameResources& f, const struct ObjectUniforms& o, VkDescriptorSet mat);
    void drawMesh(VkCommandBuffer cmd, const Mesh& m);
    void drawPack(VkCommandBuffer cmd, FrameResources& f, int index, const mat4& model, bool reflected);
    void drawOpening(VkCommandBuffer cmd, FrameResources& f);
    void drawEffects(VkCommandBuffer cmd, FrameResources& f);
    void drawAura(VkCommandBuffer cmd, FrameResources& f, const OpeningPose& pose);
    CardTextures uploadCard(const CardPixels& c, bool rare);

    VkContext& vk_;
    StageScene& scene_;
    VkDescriptorSetLayout set0Layout_ = VK_NULL_HANDLE, set1Layout_ = VK_NULL_HANDLE;
    VkPipelineLayout layout_ = VK_NULL_HANDLE;
    VkDescriptorPool pool_ = VK_NULL_HANDLE;
    VkSampler sampler_ = VK_NULL_HANDLE;
    VkPipeline pouchPipeline_ = VK_NULL_HANDLE, pouchNoCull_ = VK_NULL_HANDLE, cardPipeline_ = VK_NULL_HANDLE;
    VkPipeline reflectionPipeline_ = VK_NULL_HANDLE, shadowPipeline_ = VK_NULL_HANDLE, backgroundPipeline_ = VK_NULL_HANDLE;
    VkPipeline flakePipeline_ = VK_NULL_HANDLE, spritePipeline_ = VK_NULL_HANDLE, spriteAdditivePipeline_ = VK_NULL_HANDLE, auraPipeline_ = VK_NULL_HANDLE;
    FrameResources frames_[VkContext::framesInFlight];
    VkBuffer_ raysUBO_;
    uint32_t objectStride_ = 256;
    static constexpr uint32_t maxObjects = 512;

    VkTexture fallbackArt_, fallbackMask_, plainCardMask_, rareCardMask_, flatWrinkles_, wrinkles_, tabArt_, tabMask_;
    Mesh front_, back_, card_, tab_, tabSlider_;
    bool meshesReady_ = false;
    std::map<int, Skin> skins_;
    std::vector<CardTextures> cards_;
    std::vector<CardTextures> prepared_;
    std::map<std::pair<VkImageView, VkImageView>, Material> materials_;
    std::vector<Retired> retired_;
    struct Assets { PouchMesh front, back; WrinkleNormalMap wrinkles; };
    std::future<std::shared_ptr<Assets>> assetBuild_;
    bool builtLookValid_ = false;
    float builtPuff_ = 0, builtWrinkles_ = 0;
    std::chrono::steady_clock::time_point lastFrame_;
    bool hasLastFrame_ = false;
    float fpsAccum_ = 0, fpsWorst_ = 0; int fpsFrames_ = 0; int skip_ = 0;
};

} // namespace ck
