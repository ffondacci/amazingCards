// A small Vulkan context for the stage: device, swapchain with 4× MSAA
// and depth, frames in flight, buffers, textures and shader modules.
#pragma once
#include <vulkan/vulkan.h>
#include <android/native_window.h>
#include <android/asset_manager.h>
#include <vector>
#include <string>
#include <cstdint>
#include <functional>

namespace ck {

struct VkBuffer_ {
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkDeviceSize size = 0;
    void* mapped = nullptr;
};

struct VkTexture {
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    uint32_t width = 0, height = 0, mips = 1;
    VkFormat format = VK_FORMAT_UNDEFINED;
};

class VkContext {
public:
    static constexpr int framesInFlight = 2;

    bool init(AAssetManager* assets);
    void destroy();

    /// Binds (or releases, with null) the window the swapchain draws to.
    bool setWindow(ANativeWindow* window);
    bool hasSwapchain() const { return swapchain_ != VK_NULL_HANDLE; }
    VkExtent2D extent() const { return extent_; }
    /// Ask for the swapchain to be rebuilt at the next frame (surface resized).
    void invalidate() { outOfDate_ = true; }

    /// Acquires the next image and begins the render pass; false if nothing can be drawn this frame.
    bool beginFrame(VkCommandBuffer& cmd, int& frameIndex);
    void endFrame(VkCommandBuffer cmd);
    void waitIdle();

    VkDevice device() const { return device_; }
    VkPhysicalDevice physical() const { return physical_; }
    VkRenderPass renderPass() const { return renderPass_; }
    VkSampleCountFlagBits samples() const { return samples_; }
    VkDeviceSize uniformAlignment() const { return limits_.minUniformBufferOffsetAlignment; }
    VkDeviceSize storageAlignment() const { return limits_.minStorageBufferOffsetAlignment; }
    float maxAnisotropy() const { return anisotropy_ ? std::min(8.f, limits_.maxSamplerAnisotropy) : 1.f; }
    bool anisotropy() const { return anisotropy_; }
    uint64_t frameCounter() const { return frameCounter_; }

    VkBuffer_ createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, bool hostVisible);
    void destroyBuffer(VkBuffer_& b);
    /// Uploads RGBA8 pixels (top row first) into a mipmapped sampled texture.
    VkTexture createTexture(uint32_t w, uint32_t h, const uint8_t* rgba, bool srgb, bool mipmapped);
    void destroyTexture(VkTexture& t);
    VkShaderModule loadShader(const std::string& assetPath);

    /// One-shot command buffer helpers.
    VkCommandBuffer beginOneShot();
    void endOneShot(VkCommandBuffer cmd);

private:
    bool createInstance();
    bool pickDevice();
    bool createDevice();
    bool createSwapchain();
    void destroySwapchain();
    bool createRenderPass();
    bool createFrames();
    uint32_t memoryType(uint32_t bits, VkMemoryPropertyFlags props) const;
    VkFormat depthFormat() const;

    AAssetManager* assets_ = nullptr;
    VkInstance instance_ = VK_NULL_HANDLE;
    VkPhysicalDevice physical_ = VK_NULL_HANDLE;
    VkPhysicalDeviceLimits limits_{};
    VkPhysicalDeviceMemoryProperties memory_{};
    bool anisotropy_ = false;
    uint32_t queueFamily_ = 0;
    VkDevice device_ = VK_NULL_HANDLE;
    VkQueue queue_ = VK_NULL_HANDLE;
    VkCommandPool pool_ = VK_NULL_HANDLE;
    ANativeWindow* window_ = nullptr;
    VkSurfaceKHR surface_ = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain_ = VK_NULL_HANDLE;
    VkFormat colorFormat_ = VK_FORMAT_UNDEFINED;
    VkFormat depthFormat_ = VK_FORMAT_UNDEFINED;
    VkSampleCountFlagBits samples_ = VK_SAMPLE_COUNT_4_BIT;
    VkExtent2D extent_{0, 0};
    std::vector<VkImage> images_;
    std::vector<VkImageView> views_;
    std::vector<VkFramebuffer> framebuffers_;
    std::vector<VkSemaphore> renderDone_;
    VkTexture msaaColor_, depth_;
    VkRenderPass renderPass_ = VK_NULL_HANDLE;
    struct Frame { VkCommandBuffer cmd = VK_NULL_HANDLE; VkFence fence = VK_NULL_HANDLE; VkSemaphore acquired = VK_NULL_HANDLE; };
    Frame frames_[framesInFlight];
    int frame_ = 0;
    uint32_t imageIndex_ = 0;
    uint64_t frameCounter_ = 0;
    bool outOfDate_ = false;
};

} // namespace ck
