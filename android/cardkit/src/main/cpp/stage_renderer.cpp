#include "stage_renderer.h"
#include <android/log.h>
#include <algorithm>
#include <chrono>
#include <cstring>
#include <thread>
#include <sys/system_properties.h>

#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "CardStage", __VA_ARGS__)

namespace ck {

// Layouts mirror StageUniforms.swift and common.glsl (std140).
struct FrameUniforms {
    mat4 viewProjection;
    vec4 cameraPosition, lightDirection, lightColor, params, look, reflect, screen, screen2;
};
struct ObjectUniforms {
    mat4 model;
    vec4 flags{0, 1, 0, 1};
    vec4 tear{2, 0, 0, 0};
    vec4 cut{0, 0, 0, 0};
    vec4 glow{0, 0, 0, 0};
    vec4 peel{0, 1, 1, 0};
    vec4 mouth{0, 1, 0, 0};
};
struct RayWedge { float start, width, alpha, pad; };
struct RaysBlock { RayWedge wedges[160]; int32_t counts[4]; };
struct FlakeInstance { mat4 model; vec4 color; };
struct SpriteInstance { vec4 position, color, extra; };
static_assert(sizeof(FrameUniforms) == 192 && sizeof(ObjectUniforms) == 160, "uniform layouts");

StageRenderer::StageRenderer(VkContext& context, StageScene& scene) : vk_(context), scene_(scene) {}
StageRenderer::~StageRenderer() { destroy(); }

// MARK: - Setup

bool StageRenderer::init() {
    VkSamplerCreateInfo s{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    s.magFilter = s.minFilter = VK_FILTER_LINEAR;
    s.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    s.addressModeU = s.addressModeV = s.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    s.anisotropyEnable = vk_.anisotropy() ? VK_TRUE : VK_FALSE;
    s.maxAnisotropy = vk_.maxAnisotropy();
    s.maxLod = VK_LOD_CLAMP_NONE;
    if (vkCreateSampler(vk_.device(), &s, nullptr, &sampler_) != VK_SUCCESS) return false;

    fallbackArt_ = solid(120, 130, 150, 255, true);
    fallbackMask_ = solid(77, 25, 0, 255, false);
    plainCardMask_ = solid(0, 0, 90, 255, false);
    rareCardMask_ = solid(150, 200, 0, 255, false);
    flatWrinkles_ = solid(128, 128, 255, 255, false);
    tabMask_ = solid(255, 0, 20, 255, false);
    {
        // Gold with the dark ring hole of the pull tab.
        Pixels p; p.width = 128; p.height = 70; p.rgba.resize(128 * 70 * 4);
        float radius = 0.011f / 0.085f * 128;
        for (uint32_t y = 0; y < 70; ++y) for (uint32_t x = 0; x < 128; ++x) {
            float dx = (float)x + 0.5f - 0.29f * 128, dy = (float)y + 0.5f - 35;
            bool hole = dx * dx + dy * dy < radius * radius;
            uint8_t* px = &p.rgba[(y * 128 + x) * 4];
            px[0] = hole ? 20 : 233; px[1] = hole ? 15 : 196; px[2] = hole ? 8 : 106; px[3] = 255;
        }
        tabArt_ = texture(p, true);
    }
    card_ = upload(PouchMesh::card());
    tab_ = upload(PouchMesh::slab(0.085f, 0.046f, 0.006f, 0.014f));
    tabSlider_ = upload(PouchMesh::slab(0.034f, 0.03f, 0.016f, 0.003f));
    buildRays();
    if (!createLayouts() || !createPipelines() || !createFrames()) return false;
    rebuildAssetsIfNeeded();
    return true;
}

void StageRenderer::destroy() {
    VkDevice d = vk_.device();
    if (d == VK_NULL_HANDLE) return;
    vk_.waitIdle();
    if (assetBuild_.valid()) assetBuild_.wait();
    for (auto& [key, m] : materials_) (void)m;
    materials_.clear();
    for (auto& [i, skin] : skins_) { vk_.destroyTexture(skin.front); vk_.destroyTexture(skin.back); vk_.destroyTexture(skin.frontMask); vk_.destroyTexture(skin.backMask); }
    skins_.clear();
    auto dropCards = [&](std::vector<CardTextures>& v) { for (CardTextures& c : v) { vk_.destroyTexture(c.front); vk_.destroyTexture(c.back); if (c.ownsMask) vk_.destroyTexture(c.mask); } v.clear(); };
    dropCards(cards_); dropCards(prepared_);
    for (Retired& r : retired_) vk_.destroyTexture(r.texture);
    retired_.clear();
    for (VkTexture* t : {&fallbackArt_, &fallbackMask_, &plainCardMask_, &rareCardMask_, &flatWrinkles_, &wrinkles_, &tabArt_, &tabMask_}) vk_.destroyTexture(*t);
    for (Mesh* m : {&front_, &back_, &card_, &tab_, &tabSlider_}) destroyMesh(*m);
    for (FrameResources& f : frames_) { vk_.destroyBuffer(f.frameUBO); vk_.destroyBuffer(f.objectUBO); vk_.destroyBuffer(f.flakes); vk_.destroyBuffer(f.sprites); }
    vk_.destroyBuffer(raysUBO_);
    for (VkPipeline* p : {&pouchPipeline_, &pouchNoCull_, &cardPipeline_, &reflectionPipeline_, &shadowPipeline_, &backgroundPipeline_, &flakePipeline_, &spritePipeline_, &spriteAdditivePipeline_, &auraPipeline_}) {
        if (*p) vkDestroyPipeline(d, *p, nullptr); *p = VK_NULL_HANDLE;
    }
    if (pool_) { vkDestroyDescriptorPool(d, pool_, nullptr); pool_ = VK_NULL_HANDLE; }
    if (layout_) { vkDestroyPipelineLayout(d, layout_, nullptr); layout_ = VK_NULL_HANDLE; }
    if (set0Layout_) { vkDestroyDescriptorSetLayout(d, set0Layout_, nullptr); set0Layout_ = VK_NULL_HANDLE; }
    if (set1Layout_) { vkDestroyDescriptorSetLayout(d, set1Layout_, nullptr); set1Layout_ = VK_NULL_HANDLE; }
    if (sampler_) { vkDestroySampler(d, sampler_, nullptr); sampler_ = VK_NULL_HANDLE; }
}

bool StageRenderer::createLayouts() {
    VkDevice d = vk_.device();
    VkDescriptorSetLayoutBinding b0[6]{};
    b0[0] = {0, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    b0[1] = {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, 1, VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    b0[2] = {2, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    b0[3] = {3, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    b0[4] = {4, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_VERTEX_BIT, nullptr};
    b0[5] = {5, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_VERTEX_BIT, nullptr};
    VkDescriptorSetLayoutCreateInfo l0{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    l0.bindingCount = 6; l0.pBindings = b0;
    if (vkCreateDescriptorSetLayout(d, &l0, nullptr, &set0Layout_) != VK_SUCCESS) return false;
    VkDescriptorSetLayoutBinding b1[2]{};
    b1[0] = {0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    b1[1] = {1, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, nullptr};
    VkDescriptorSetLayoutCreateInfo l1{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    l1.bindingCount = 2; l1.pBindings = b1;
    if (vkCreateDescriptorSetLayout(d, &l1, nullptr, &set1Layout_) != VK_SUCCESS) return false;
    VkDescriptorSetLayout sets[2] = {set0Layout_, set1Layout_};
    VkPipelineLayoutCreateInfo pl{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    pl.setLayoutCount = 2; pl.pSetLayouts = sets;
    if (vkCreatePipelineLayout(d, &pl, nullptr, &layout_) != VK_SUCCESS) return false;
    VkDescriptorPoolSize sizes[4] = {
        {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 8}, {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, 4},
        {VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 4 + 2 * 512}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 8}};
    VkDescriptorPoolCreateInfo pool{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pool.flags = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;
    pool.maxSets = 2 + 512;
    pool.poolSizeCount = 4; pool.pPoolSizes = sizes;
    return vkCreateDescriptorPool(d, &pool, nullptr, &pool_) == VK_SUCCESS;
}

VkPipeline StageRenderer::pipeline(const char* vert, const char* frag, Blend blend, bool coverage, VkCullModeFlags cull, Depth depth, bool vertexInput) {
    VkDevice d = vk_.device();
    VkShaderModule vs = vk_.loadShader(std::string("shaders/") + vert + ".spv");
    VkShaderModule fs = vk_.loadShader(std::string("shaders/") + frag + ".spv");
    if (!vs || !fs) return VK_NULL_HANDLE;
    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0] = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_VERTEX_BIT, vs, "main", nullptr};
    stages[1] = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_FRAGMENT_BIT, fs, "main", nullptr};
    VkVertexInputBindingDescription binding{0, sizeof(PouchVertex), VK_VERTEX_INPUT_RATE_VERTEX};
    VkVertexInputAttributeDescription attrs[3] = {
        {0, 0, VK_FORMAT_R32G32B32_SFLOAT, 0}, {1, 0, VK_FORMAT_R32G32B32_SFLOAT, 16}, {2, 0, VK_FORMAT_R32G32_SFLOAT, 32}};
    VkPipelineVertexInputStateCreateInfo vi{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    if (vertexInput) { vi.vertexBindingDescriptionCount = 1; vi.pVertexBindingDescriptions = &binding; vi.vertexAttributeDescriptionCount = 3; vi.pVertexAttributeDescriptions = attrs; }
    VkPipelineInputAssemblyStateCreateInfo ia{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkPipelineViewportStateCreateInfo vp{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    vp.viewportCount = 1; vp.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo rs{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    rs.polygonMode = VK_POLYGON_MODE_FILL;
    rs.cullMode = cull;
    rs.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rs.lineWidth = 1;
    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples = vk_.samples();
    ms.alphaToCoverageEnable = coverage ? VK_TRUE : VK_FALSE;
    VkPipelineDepthStencilStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    ds.depthTestEnable = depth == Depth::none ? VK_FALSE : VK_TRUE;
    ds.depthWriteEnable = depth == Depth::write ? VK_TRUE : VK_FALSE;
    ds.depthCompareOp = depth == Depth::none ? VK_COMPARE_OP_ALWAYS : VK_COMPARE_OP_LESS;
    VkPipelineColorBlendAttachmentState cb{};
    cb.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    cb.blendEnable = blend != Blend::none ? VK_TRUE : VK_FALSE;
    switch (blend) {
        case Blend::none: break;
        case Blend::alpha: cb.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA; cb.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA; break;
        case Blend::premultiplied: cb.srcColorBlendFactor = VK_BLEND_FACTOR_ONE; cb.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA; break;
        case Blend::additive: cb.srcColorBlendFactor = VK_BLEND_FACTOR_ONE; cb.dstColorBlendFactor = VK_BLEND_FACTOR_ONE; break;
    }
    cb.colorBlendOp = VK_BLEND_OP_ADD;
    cb.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    cb.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    cb.alphaBlendOp = VK_BLEND_OP_ADD;
    VkPipelineColorBlendStateCreateInfo blendState{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    blendState.attachmentCount = 1; blendState.pAttachments = &cb;
    VkDynamicState dynamics[2] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dyn{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    dyn.dynamicStateCount = 2; dyn.pDynamicStates = dynamics;
    VkGraphicsPipelineCreateInfo info{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    info.stageCount = 2; info.pStages = stages;
    info.pVertexInputState = &vi;
    info.pInputAssemblyState = &ia;
    info.pViewportState = &vp;
    info.pRasterizationState = &rs;
    info.pMultisampleState = &ms;
    info.pDepthStencilState = &ds;
    info.pColorBlendState = &blendState;
    info.pDynamicState = &dyn;
    info.layout = layout_;
    info.renderPass = vk_.renderPass();
    VkPipeline p = VK_NULL_HANDLE;
    if (vkCreateGraphicsPipelines(d, VK_NULL_HANDLE, 1, &info, nullptr, &p) != VK_SUCCESS) LOGE("pipeline %s/%s failed", vert, frag);
    vkDestroyShaderModule(d, vs, nullptr);
    vkDestroyShaderModule(d, fs, nullptr);
    return p;
}

bool StageRenderer::createPipelines() {
    pouchPipeline_ = pipeline("pouch.vert", "pouch.frag", Blend::none, true, VK_CULL_MODE_BACK_BIT, Depth::write, true);
    pouchNoCull_ = pipeline("pouch.vert", "pouch.frag", Blend::none, true, VK_CULL_MODE_NONE, Depth::write, true);
    cardPipeline_ = pipeline("pouch.vert", "pouch.frag", Blend::none, true, VK_CULL_MODE_BACK_BIT, Depth::read, true);
    reflectionPipeline_ = pipeline("pouch.vert", "pouch.frag", Blend::alpha, false, VK_CULL_MODE_FRONT_BIT, Depth::read, true);
    shadowPipeline_ = pipeline("sprite.vert", "shadow.frag", Blend::alpha, false, VK_CULL_MODE_NONE, Depth::read, false);
    backgroundPipeline_ = pipeline("background.vert", "background.frag", Blend::none, false, VK_CULL_MODE_NONE, Depth::none, false);
    flakePipeline_ = pipeline("flake.vert", "flake.frag", Blend::none, false, VK_CULL_MODE_NONE, Depth::write, false);
    spritePipeline_ = pipeline("particle.vert", "particle.frag", Blend::premultiplied, false, VK_CULL_MODE_NONE, Depth::read, false);
    spriteAdditivePipeline_ = pipeline("particle.vert", "particle.frag", Blend::additive, false, VK_CULL_MODE_NONE, Depth::read, false);
    auraPipeline_ = pipeline("sprite.vert", "aura.frag", Blend::additive, false, VK_CULL_MODE_NONE, Depth::none, false);
    for (VkPipeline p : {pouchPipeline_, pouchNoCull_, cardPipeline_, reflectionPipeline_, shadowPipeline_, backgroundPipeline_, flakePipeline_, spritePipeline_, spriteAdditivePipeline_, auraPipeline_}) {
        if (p == VK_NULL_HANDLE) return false;
    }
    return true;
}

bool StageRenderer::createFrames() {
    VkDevice d = vk_.device();
    uint32_t align = (uint32_t)std::max<VkDeviceSize>(vk_.uniformAlignment(), 16);
    objectStride_ = ((uint32_t)sizeof(ObjectUniforms) + align - 1) / align * align;
    for (FrameResources& f : frames_) {
        f.frameUBO = vk_.createBuffer(sizeof(FrameUniforms), VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, true);
        f.objectUBO = vk_.createBuffer((VkDeviceSize)objectStride_ * maxObjects, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, true);
        f.flakes = vk_.createBuffer(sizeof(FlakeInstance) * StageParticles::flakeCount, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, true);
        f.sprites = vk_.createBuffer(sizeof(SpriteInstance) * (StageParticles::sparkCount + StageParticles::puffCount), VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, true);
        VkDescriptorSetAllocateInfo alloc{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
        alloc.descriptorPool = pool_;
        alloc.descriptorSetCount = 1;
        alloc.pSetLayouts = &set0Layout_;
        if (vkAllocateDescriptorSets(d, &alloc, &f.set0) != VK_SUCCESS) return false;
        VkDescriptorBufferInfo frameInfo{f.frameUBO.buffer, 0, sizeof(FrameUniforms)};
        VkDescriptorBufferInfo objectInfo{f.objectUBO.buffer, 0, sizeof(ObjectUniforms)};
        VkDescriptorBufferInfo raysInfo{raysUBO_.buffer, 0, sizeof(RaysBlock)};
        VkDescriptorBufferInfo flakeInfo{f.flakes.buffer, 0, VK_WHOLE_SIZE};
        VkDescriptorBufferInfo spriteInfo{f.sprites.buffer, 0, VK_WHOLE_SIZE};
        VkDescriptorImageInfo wrinkleInfo{sampler_, flatWrinkles_.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        VkWriteDescriptorSet writes[6]{};
        for (int i = 0; i < 6; ++i) { writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = f.set0; writes[i].dstBinding = (uint32_t)i; writes[i].descriptorCount = 1; }
        writes[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER; writes[0].pBufferInfo = &frameInfo;
        writes[1].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC; writes[1].pBufferInfo = &objectInfo;
        writes[2].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; writes[2].pImageInfo = &wrinkleInfo;
        writes[3].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER; writes[3].pBufferInfo = &raysInfo;
        writes[4].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; writes[4].pBufferInfo = &flakeInfo;
        writes[5].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; writes[5].pBufferInfo = &spriteInfo;
        vkUpdateDescriptorSets(d, 6, writes, 0, nullptr);
    }
    return true;
}

/// Wedges of the two ray layers, like the stage's conic gradients.
void StageRenderer::buildRays() {
    RaysBlock block{};
    int n = 0;
    auto layer = [&](uint32_t seed, float minWidth, float maxWidth, float gap, float gapRandom) {
        noise::Generator gen(seed);
        int count = 0;
        float angle = gen.next() * gapRandom;
        while (angle < 360 - maxWidth && n < 160) {
            float width = minWidth + gen.next() * (maxWidth - minWidth);
            float alpha = 0.3f + 0.7f * std::pow(gen.next(), 1.5f);
            block.wedges[n++] = {angle, width, alpha, 0};
            count += 1;
            angle += width + gap + gen.next() * (gapRandom - gap);
        }
        return count;
    };
    block.counts[0] = layer(7, 2.2f, 7.5f, 5, 16);
    block.counts[1] = layer(31, 0.5f, 1.6f, 3, 9);
    raysUBO_ = vk_.createBuffer(sizeof(RaysBlock), VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, true);
    memcpy(raysUBO_.mapped, &block, sizeof block);
}

// MARK: - Resources

VkTexture StageRenderer::solid(uint8_t r, uint8_t g, uint8_t b, uint8_t a, bool srgb) {
    uint8_t px[4] = {r, g, b, a};
    return vk_.createTexture(1, 1, px, srgb, false);
}

VkTexture StageRenderer::texture(const Pixels& p, bool srgb) {
    if (p.empty()) return VkTexture();
    return vk_.createTexture(p.width, p.height, p.rgba.data(), srgb, true);
}

StageRenderer::Mesh StageRenderer::upload(const PouchMesh& mesh) {
    Mesh m;
    m.vertices = vk_.createBuffer(mesh.vertices.size() * sizeof(PouchVertex), VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, true);
    memcpy(m.vertices.mapped, mesh.vertices.data(), mesh.vertices.size() * sizeof(PouchVertex));
    m.indices = vk_.createBuffer(mesh.indices.size() * sizeof(uint32_t), VK_BUFFER_USAGE_INDEX_BUFFER_BIT, true);
    memcpy(m.indices.mapped, mesh.indices.data(), mesh.indices.size() * sizeof(uint32_t));
    m.count = (uint32_t)mesh.indices.size();
    return m;
}

void StageRenderer::destroyMesh(Mesh& m) { vk_.destroyBuffer(m.vertices); vk_.destroyBuffer(m.indices); m.count = 0; }

void StageRenderer::retire(VkTexture& t) {
    if (t.image == VK_NULL_HANDLE) return;
    for (auto it = materials_.begin(); it != materials_.end();) {
        if (it->first.first == t.view || it->first.second == t.view) {
            vkFreeDescriptorSets(vk_.device(), pool_, 1, &it->second.set);
            it = materials_.erase(it);
        } else ++it;
    }
    retired_.push_back({t, vk_.frameCounter()});
    t = VkTexture();
}

void StageRenderer::sweepRetired() {
    uint64_t now = vk_.frameCounter();
    for (auto it = retired_.begin(); it != retired_.end();) {
        if (now - it->frame > VkContext::framesInFlight + 1) { vk_.destroyTexture(it->texture); it = retired_.erase(it); }
        else ++it;
    }
}

VkDescriptorSet StageRenderer::material(const VkTexture& art, const VkTexture& mask) {
    auto key = std::make_pair(art.view, mask.view);
    auto it = materials_.find(key);
    if (it != materials_.end()) return it->second.set;
    VkDescriptorSetAllocateInfo alloc{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    alloc.descriptorPool = pool_;
    alloc.descriptorSetCount = 1;
    alloc.pSetLayouts = &set1Layout_;
    Material m;
    if (vkAllocateDescriptorSets(vk_.device(), &alloc, &m.set) != VK_SUCCESS) return VK_NULL_HANDLE;
    VkDescriptorImageInfo infos[2] = {{sampler_, art.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL}, {sampler_, mask.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL}};
    VkWriteDescriptorSet writes[2]{};
    for (int i = 0; i < 2; ++i) {
        writes[i].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET; writes[i].dstSet = m.set; writes[i].dstBinding = (uint32_t)i;
        writes[i].descriptorCount = 1; writes[i].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; writes[i].pImageInfo = &infos[i];
    }
    vkUpdateDescriptorSets(vk_.device(), 2, writes, 0, nullptr);
    materials_[key] = m;
    return m.set;
}

void StageRenderer::setSkin(int index, const SkinPixels* skin) {
    auto it = skins_.find(index);
    if (!skin) {
        if (it != skins_.end()) { retire(it->second.front); retire(it->second.back); retire(it->second.frontMask); retire(it->second.backMask); skins_.erase(it); }
        return;
    }
    if (it != skins_.end() && it->second.id == skin->id) return;
    if (it != skins_.end()) { retire(it->second.front); retire(it->second.back); retire(it->second.frontMask); retire(it->second.backMask); skins_.erase(it); }
    Skin s;
    s.id = skin->id;
    s.front = texture(skin->front, true);
    s.back = skin->back.empty() ? VkTexture() : texture(skin->back, true);
    s.frontMask = skin->frontMask.empty() ? VkTexture() : texture(skin->frontMask, false);
    s.backMask = skin->backMask.empty() ? VkTexture() : texture(skin->backMask, false);
    skins_[index] = s;
}

StageRenderer::CardTextures StageRenderer::uploadCard(const CardPixels& c, bool rare) {
    CardTextures t;
    t.id = c.id;
    t.front = texture(c.front, true);
    t.back = texture(c.back, true);
    if (c.mask.empty()) { t.mask = rare ? rareCardMask_ : plainCardMask_; t.ownsMask = false; }
    else { t.mask = texture(c.mask, false); t.ownsMask = true; }
    return t;
}

void StageRenderer::prepareCards(std::vector<CardPixels> cards) {
    for (CardTextures& c : prepared_) { retire(c.front); retire(c.back); if (c.ownsMask) retire(c.mask); }
    prepared_.clear();
    int last = (int)cards.size() - 1;
    for (int i = 0; i < (int)cards.size(); ++i) prepared_.push_back(uploadCard(cards[i], i == last && scene_.settings().rareLast));
}

void StageRenderer::dealPrepared() {
    for (CardTextures& c : cards_) { retire(c.front); retire(c.back); if (c.ownsMask) retire(c.mask); }
    cards_ = std::move(prepared_);
    prepared_.clear();
    if (!cards_.empty() && cards_[0].front.height > 0) {
        scene_.cardAspect = (float)cards_[0].front.width / (float)cards_[0].front.height;
    }
}

void StageRenderer::rebuildAssetsIfNeeded() {
    const StageSettings& s = scene_.settings();
    if (builtLookValid_ && builtPuff_ == s.puff && builtWrinkles_ == s.wrinkles) return;
    if (assetBuild_.valid()) return; // one build at a time; checked again once it lands
    builtLookValid_ = true; builtPuff_ = s.puff; builtWrinkles_ = s.wrinkles;
    float puff = s.puff, wrinkles = s.wrinkles;
    bool needMap = wrinkles_.image == VK_NULL_HANDLE;
    assetBuild_ = std::async(std::launch::async, [puff, wrinkles, needMap]() {
        auto a = std::make_shared<Assets>();
        a->front = PouchMesh::make(false, 11, puff, wrinkles);
        a->back = PouchMesh::make(true, 29, puff, wrinkles);
        if (needMap) a->wrinkles = WrinkleNormalMap::make();
        return a;
    });
}

void StageRenderer::bindWrinkles(FrameResources& f) {
    if (f.wrinklesBound || wrinkles_.image == VK_NULL_HANDLE) return;
    VkDescriptorImageInfo info{sampler_, wrinkles_.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkWriteDescriptorSet write{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
    write.dstSet = f.set0; write.dstBinding = 2; write.descriptorCount = 1;
    write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; write.pImageInfo = &info;
    vkUpdateDescriptorSets(vk_.device(), 1, &write, 0, nullptr);
    f.wrinklesBound = true;
}

// MARK: - Frame

uint32_t StageRenderer::pushObject(FrameResources& f, const ObjectUniforms& o) {
    uint32_t slot = std::min(f.objectCursor++, maxObjects - 1);
    uint32_t offset = slot * objectStride_;
    memcpy((uint8_t*)f.objectUBO.mapped + offset, &o, sizeof o);
    return offset;
}

void StageRenderer::bindObject(VkCommandBuffer cmd, FrameResources& f, const ObjectUniforms& o, VkDescriptorSet mat) {
    uint32_t offset = pushObject(f, o);
    VkDescriptorSet sets[2] = {f.set0, mat ? mat : material(fallbackArt_, fallbackMask_)};
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, layout_, 0, 2, sets, 1, &offset);
}

void StageRenderer::drawMesh(VkCommandBuffer cmd, const Mesh& m) {
    VkDeviceSize zero = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, &m.vertices.buffer, &zero);
    vkCmdBindIndexBuffer(cmd, m.indices.buffer, 0, VK_INDEX_TYPE_UINT32);
    vkCmdDrawIndexed(cmd, m.count, 1, 0, 0, 0);
}

void StageRenderer::render() {
    auto now = std::chrono::steady_clock::now();
    float dt = hasLastFrame_ ? std::chrono::duration<float>(now - lastFrame_).count() : 1.f / 60;
    lastFrame_ = now; hasLastFrame_ = true;
    // Frame pacing in logcat every two seconds (`adb logcat -s CardStage`).
    fpsAccum_ += dt; fpsWorst_ = std::max(fpsWorst_, dt); fpsFrames_ += 1;
    if (fpsAccum_ >= 2.f) {
        __android_log_print(ANDROID_LOG_INFO, "CardStage", "fps %.0f (worst frame %.1f ms)", fpsFrames_ / fpsAccum_, fpsWorst_ * 1000);
        fpsAccum_ = 0; fpsWorst_ = 0; fpsFrames_ = 0;
    }

    if (assetBuild_.valid() && assetBuild_.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
        auto a = assetBuild_.get();
        vk_.waitIdle();
        destroyMesh(front_); destroyMesh(back_);
        front_ = upload(a->front); back_ = upload(a->back);
        if (wrinkles_.image == VK_NULL_HANDLE && !a->wrinkles.rgba.empty()) {
            wrinkles_ = vk_.createTexture(WrinkleNormalMap::width, WrinkleNormalMap::height, a->wrinkles.rgba.data(), false, true);
            for (FrameResources& f : frames_) f.wrinklesBound = false;
        }
        meshesReady_ = true;
        __android_log_print(ANDROID_LOG_INFO, "CardStage", "meshes ready: %u / %u indices, wrinkles %u", front_.count, back_.count, wrinkles_.mips);
    }
    rebuildAssetsIfNeeded();
    scene_.advance(dt);
    sweepRetired();

    VkCommandBuffer cmd; int frameIndex;
    if (!vk_.beginFrame(cmd, frameIndex)) return;
    FrameResources& f = frames_[frameIndex];
    f.objectCursor = 0;
    bindWrinkles(f);

    const StageSettings& settings = scene_.settings();
    bool night = settings.lighting == Lighting::night;
    const StageCamera& cam = scene_.camera();
    FrameUniforms frame;
    frame.viewProjection = cam.viewProjection();
    frame.cameraPosition = vec4(cam.position, 1);
    vec3 ld = normalize(vec3(-2.5f, 3.5f, 4.5f));
    frame.lightDirection = vec4(ld, night ? 0.9f : 1.4f);
    frame.lightColor = night ? vec4(0.784f, 0.831f, 1.f, 1) : vec4(1, 1, 1, 1);
    frame.params = vec4(scene_.time(), scene_.sweep(), night ? 1.f : 0.f, pouch::floorY);
    frame.look = vec4(settings.foil, settings.holo, settings.gloss, settings.shine);
    frame.reflect = vec4(0.85f, 0.5f * settings.reflection, 0.25f + 1.75f * settings.wrinkles, 0);
    float flash = 0;
    if (scene_.burstTime() >= 0) flash = std::max(0.f, 1 - (float)((scene_.clock() - scene_.burstTime()) / 0.6));
    frame.screen = vec4(scene_.floorLine(), scene_.raysLevel(), scene_.raysLevel(), scene_.dimLevel());
    frame.screen2 = vec4(scene_.openingPose().premium ? 1.f : 0.f, scene_.viewport().x, scene_.viewport().y, flash * flash);
    memcpy(f.frameUBO.mapped, &frame, sizeof frame);

    // Debug switches: `adb shell setprop debug.cardstage.skip <bits>` (1 reflections, 2 packs, 4 shadows, 8 background, 16 opening).
    if (vk_.frameCounter() % 2 == 0) { char v[PROP_VALUE_MAX] = "0"; __system_property_get("debug.cardstage.skip", v); skip_ = atoi(v); }
    ObjectUniforms none;
    if (settings.background && !(skip_ & 8)) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, backgroundPipeline_);
        bindObject(cmd, f, none, VK_NULL_HANDLE);
        vkCmdDraw(cmd, 3, 1, 0, 0);
    }
    if (meshesReady_) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pouchPipeline_);
        const auto& poses = scene_.poses();
        if (!(skip_ & 2)) for (size_t i = 0; i < poses.size(); ++i) if (poses[i].visible) drawPack(cmd, f, (int)i, poses[i].model, false);
        if (!(skip_ & 16)) drawOpening(cmd, f);
        drawEffects(cmd, f);
        if (settings.reflection > 0 && !(skip_ & 1)) {
            vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, reflectionPipeline_);
            mat4 mirror = mirrorY(pouch::floorY);
            for (size_t i = 0; i < poses.size(); ++i) if (poses[i].visible) drawPack(cmd, f, (int)i, mirror * poses[i].model, true);
        }
    }
    if (settings.shadow > 0 && !(skip_ & 4)) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, shadowPipeline_);
        for (const PackPose& pose : scene_.poses()) {
            if (!pose.visible || pose.shadowOpacity <= 0.001f) continue;
            ObjectUniforms o; o.model = pose.shadowModel; o.flags = vec4(0, 1, 0, pose.shadowOpacity);
            bindObject(cmd, f, o, VK_NULL_HANDLE);
            vkCmdDraw(cmd, 6, 1, 0, 0);
        }
    }
    vk_.endFrame(cmd);
}

void StageRenderer::drawPack(VkCommandBuffer cmd, FrameResources& f, int index, const mat4& model, bool reflected) {
    auto it = skins_.find(index);
    const Skin* skin = it != skins_.end() ? &it->second : nullptr;
    const VkTexture& front = skin && skin->front.image ? skin->front : fallbackArt_;
    const VkTexture& back = skin && skin->back.image ? skin->back : front;
    const VkTexture& frontMask = skin && skin->frontMask.image ? skin->frontMask : fallbackMask_;
    const VkTexture& backMask = skin && skin->backMask.image ? skin->backMask : frontMask;
    ObjectUniforms o;
    o.model = model;
    o.flags = vec4(reflected ? 1.f : 0.f, 1, 1, 1);
    bindObject(cmd, f, o, material(front, frontMask));
    drawMesh(cmd, front_);
    o.model = model * rotationY((float)M_PI);
    o.flags.y = -1;
    bindObject(cmd, f, o, material(back, backMask));
    drawMesh(cmd, back_);
}

static void setDials(ObjectUniforms& o, const PieceDials& d) {
    o.tear = vec4(d.tearV, d.tearSide, d.cutP, d.inside);
    o.cut = vec4(d.lineMode, d.cutDir, d.perf, d.heat);
    o.glow = vec4(d.tipGlow, d.dissolve, d.innerGlow, d.guide);
    o.peel = vec4(d.peel, d.peelDir, d.peelAmt, d.fly);
    o.mouth = vec4(d.mouth, d.mouthK, 0, 0);
}

void StageRenderer::drawOpening(VkCommandBuffer cmd, FrameResources& f) {
    const OpeningPose& pose = scene_.openingPose();
    if (!pose.visible) return;
    auto it = skins_.find(scene_.openingPack());
    const Skin* skin = it != skins_.end() ? &it->second : nullptr;
    const VkTexture& front = skin && skin->front.image ? skin->front : fallbackArt_;
    const VkTexture& back = skin && skin->back.image ? skin->back : front;
    const VkTexture& frontMask = skin && skin->frontMask.image ? skin->frontMask : fallbackMask_;
    const VkTexture& backMask = skin && skin->backMask.image ? skin->backMask : frontMask;
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pouchNoCull_);
    auto piece = [&](const mat4& model, const PieceDials& dials) {
        for (int isBack = 0; isBack < 2; ++isBack) {
            ObjectUniforms o;
            o.model = isBack ? model * rotationY((float)M_PI) : model;
            o.flags = vec4(0, isBack ? -1.f : 1.f, 1, 1);
            setDials(o, dials);
            bindObject(cmd, f, o, material(isBack ? back : front, isBack ? backMask : frontMask));
            drawMesh(cmd, isBack ? back_ : front_);
        }
    };
    if (pose.bodyVisible) piece(pose.bodyModel, pose.body);
    if (pose.stripVisible) piece(pose.stripModel, pose.strip);
    if (pose.tabVisible) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pouchPipeline_);
        for (const Mesh* m : {&tab_, &tabSlider_}) {
            ObjectUniforms o; o.model = pose.tabModel; o.flags = vec4(0, 1, 0, 1); o.mouth = vec4(0, 1, 1, 0);
            bindObject(cmd, f, o, material(tabArt_, tabMask_));
            drawMesh(cmd, *m);
        }
    }
    if (pose.cards.empty()) return;
    drawAura(cmd, f, pose);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, cardPipeline_);
    std::vector<int> order(pose.cards.size());
    for (size_t i = 0; i < order.size(); ++i) order[i] = (int)i;
    std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return pose.cards[a].order < pose.cards[b].order; });
    for (int i : order) {
        if (i >= (int)cards_.size()) continue;
        const CardTextures& t = cards_[i];
        const OpeningPose::CardDraw& draw = pose.cards[i];
        for (int isBack = 0; isBack < 2; ++isBack) {
            mat4 offset = translation({0, 0, isBack ? -0.0006f : 0.0006f});
            ObjectUniforms o;
            o.model = draw.model * offset * (isBack ? rotationY((float)M_PI) : mat4());
            o.flags = vec4(0, 1, 0, 1);
            o.mouth = vec4(0, 1, 1, draw.emissive);
            bindObject(cmd, f, o, material(isBack ? t.back : t.front, isBack ? plainCardMask_ : t.mask));
            drawMesh(cmd, card_);
        }
    }
}

void StageRenderer::drawEffects(VkCommandBuffer cmd, FrameResources& f) {
    const StageParticles& particles = scene_.particles();
    bool night = scene_.settings().lighting == Lighting::night;
    FlakeInstance* flakes = (FlakeInstance*)f.flakes.mapped;
    uint32_t nFlakes = 0;
    for (const auto& fl : particles.flakes) {
        if (fl.life <= 0) continue;
        float size = StageParticles::scaleOf(fl);
        flakes[nFlakes].model = translation(fl.position) * fl.rotation.matrix() * scale(vec3(size));
        flakes[nFlakes].color = vec4(fl.color, 1);
        nFlakes += 1;
    }
    ObjectUniforms none;
    if (nFlakes > 0) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, flakePipeline_);
        bindObject(cmd, f, none, VK_NULL_HANDLE);
        vkCmdDraw(cmd, 6, nFlakes, 0, 0);
    }
    SpriteInstance* sprites = (SpriteInstance*)f.sprites.mapped;
    uint32_t nSprites = 0;
    vec3 smoke = night ? vec3(0.788f, 0.839f, 0.902f) : vec3(0.553f, 0.557f, 0.592f);
    for (const auto& q : particles.puffs) {
        if (q.life <= 0) continue;
        float size, opacity; StageParticles::lookOf(q, size, opacity);
        sprites[nSprites++] = {vec4(q.position, size), vec4(smoke, opacity), vec4(q.angle, 1, 0, 0)};
    }
    for (const auto& k : particles.sparks) {
        if (k.life <= 0) continue;
        sprites[nSprites++] = {vec4(k.position, 0.11f), vec4(k.color, StageParticles::alphaOf(k)), vec4(0, 0, 0, 0)};
    }
    if (nSprites > 0) {
        vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, night ? spriteAdditivePipeline_ : spritePipeline_);
        bindObject(cmd, f, none, VK_NULL_HANDLE);
        vkCmdDraw(cmd, 6, nSprites, 0, 0);
    }
}

void StageRenderer::drawAura(VkCommandBuffer cmd, FrameResources& f, const OpeningPose& pose) {
    if (pose.auraOpacity <= 0.01f || pose.cards.empty()) return;
    const OpeningPose::CardDraw& last = pose.cards.back();
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, auraPipeline_);
    float cardW = StageScene::cardWidth, cardH = scene_.cardHeight();
    float pulse = 1 + 0.05f * std::sin(scene_.time() * 3.2f) + 0.45f * pose.auraPulse;
    ObjectUniforms glow;
    glow.model = last.model * translation({0, 0, -0.03f}) * scale({cardW * 2.4f * pulse, cardH * 2 * pulse, 1});
    glow.flags = vec4(0, 1, 0, std::min(1.f, 0.8f * pose.auraOpacity + 0.4f * pose.auraPulse));
    bindObject(cmd, f, glow, VK_NULL_HANDLE);
    vkCmdDraw(cmd, 6, 1, 0, 0);
    float raySize = cardH * 3 * pulse;
    ObjectUniforms rays;
    rays.model = last.model * translation({0, 0, -0.04f}) * rotationZ(0.05f * std::sin(scene_.time() * 0.3f)) * scale({raySize, raySize, 1});
    rays.flags = vec4(0, 1, 1, 0.55f * pose.auraOpacity);
    bindObject(cmd, f, rays, VK_NULL_HANDLE);
    vkCmdDraw(cmd, 6, 1, 0, 0);
}

} // namespace ck
