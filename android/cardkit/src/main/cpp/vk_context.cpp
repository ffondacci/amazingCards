#include "vk_context.h"
#include <android/log.h>
#include <algorithm>
#include <cstring>

#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "CardStage", __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "CardStage", __VA_ARGS__)
#define VK_CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { LOGE("%s failed: %d", #x, (int)r_); return false; } } while (0)

namespace ck {

bool VkContext::init(AAssetManager* assets) {
    assets_ = assets;
    if (!createInstance() || !pickDevice() || !createDevice() || !createFrames()) return false;
    return true;
}

void VkContext::destroy() {
    if (device_ != VK_NULL_HANDLE) vkDeviceWaitIdle(device_);
    destroySwapchain();
    if (renderPass_) { vkDestroyRenderPass(device_, renderPass_, nullptr); renderPass_ = VK_NULL_HANDLE; }
    for (Frame& f : frames_) {
        if (f.fence) vkDestroyFence(device_, f.fence, nullptr);
        if (f.acquired) vkDestroySemaphore(device_, f.acquired, nullptr);
        f = Frame();
    }
    if (pool_) { vkDestroyCommandPool(device_, pool_, nullptr); pool_ = VK_NULL_HANDLE; }
    if (surface_) { vkDestroySurfaceKHR(instance_, surface_, nullptr); surface_ = VK_NULL_HANDLE; }
    if (window_) { ANativeWindow_release(window_); window_ = nullptr; }
    if (device_) { vkDestroyDevice(device_, nullptr); device_ = VK_NULL_HANDLE; }
    if (instance_) { vkDestroyInstance(instance_, nullptr); instance_ = VK_NULL_HANDLE; }
}

bool VkContext::createInstance() {
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "CardStage";
    app.apiVersion = VK_API_VERSION_1_1;
    const char* extensions[] = {VK_KHR_SURFACE_EXTENSION_NAME, "VK_KHR_android_surface"};
    VkInstanceCreateInfo info{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    info.pApplicationInfo = &app;
    info.enabledExtensionCount = 2;
    info.ppEnabledExtensionNames = extensions;
    VK_CHECK(vkCreateInstance(&info, nullptr, &instance_));
    return true;
}

bool VkContext::pickDevice() {
    uint32_t count = 0;
    vkEnumeratePhysicalDevices(instance_, &count, nullptr);
    if (count == 0) { LOGE("no Vulkan device"); return false; }
    std::vector<VkPhysicalDevice> devices(count);
    vkEnumeratePhysicalDevices(instance_, &count, devices.data());
    for (VkPhysicalDevice d : devices) {
        uint32_t n = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(d, &n, nullptr);
        std::vector<VkQueueFamilyProperties> families(n);
        vkGetPhysicalDeviceQueueFamilyProperties(d, &n, families.data());
        for (uint32_t i = 0; i < n; ++i) {
            if (families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
                physical_ = d; queueFamily_ = i;
                VkPhysicalDeviceProperties props;
                vkGetPhysicalDeviceProperties(d, &props);
                limits_ = props.limits;
                vkGetPhysicalDeviceMemoryProperties(d, &memory_);
                VkPhysicalDeviceFeatures features;
                vkGetPhysicalDeviceFeatures(d, &features);
                anisotropy_ = features.samplerAnisotropy == VK_TRUE;
                VkSampleCountFlags ok = limits_.framebufferColorSampleCounts & limits_.framebufferDepthSampleCounts;
                samples_ = (ok & VK_SAMPLE_COUNT_4_BIT) ? VK_SAMPLE_COUNT_4_BIT : (ok & VK_SAMPLE_COUNT_2_BIT) ? VK_SAMPLE_COUNT_2_BIT : VK_SAMPLE_COUNT_1_BIT;
                LOGI("Vulkan device: %s (api %u.%u), samples %d", props.deviceName, VK_VERSION_MAJOR(props.apiVersion), VK_VERSION_MINOR(props.apiVersion), (int)samples_);
                return true;
            }
        }
    }
    LOGE("no graphics queue");
    return false;
}

bool VkContext::createDevice() {
    float priority = 1;
    VkDeviceQueueCreateInfo q{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    q.queueFamilyIndex = queueFamily_;
    q.queueCount = 1;
    q.pQueuePriorities = &priority;
    VkPhysicalDeviceFeatures features{};
    features.samplerAnisotropy = anisotropy_ ? VK_TRUE : VK_FALSE;
    const char* extensions[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    VkDeviceCreateInfo info{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    info.queueCreateInfoCount = 1;
    info.pQueueCreateInfos = &q;
    info.enabledExtensionCount = 1;
    info.ppEnabledExtensionNames = extensions;
    info.pEnabledFeatures = &features;
    VK_CHECK(vkCreateDevice(physical_, &info, nullptr, &device_));
    vkGetDeviceQueue(device_, queueFamily_, 0, &queue_);
    VkCommandPoolCreateInfo pool{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pool.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool.queueFamilyIndex = queueFamily_;
    VK_CHECK(vkCreateCommandPool(device_, &pool, nullptr, &pool_));
    return true;
}

bool VkContext::createFrames() {
    for (Frame& f : frames_) {
        VkCommandBufferAllocateInfo alloc{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        alloc.commandPool = pool_;
        alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        alloc.commandBufferCount = 1;
        VK_CHECK(vkAllocateCommandBuffers(device_, &alloc, &f.cmd));
        VkFenceCreateInfo fence{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
        fence.flags = VK_FENCE_CREATE_SIGNALED_BIT;
        VK_CHECK(vkCreateFence(device_, &fence, nullptr, &f.fence));
        VkSemaphoreCreateInfo sem{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        VK_CHECK(vkCreateSemaphore(device_, &sem, nullptr, &f.acquired));
    }
    return true;
}

VkFormat VkContext::depthFormat() const {
    for (VkFormat f : {VK_FORMAT_D32_SFLOAT, VK_FORMAT_D24_UNORM_S8_UINT, VK_FORMAT_D32_SFLOAT_S8_UINT, VK_FORMAT_D16_UNORM}) {
        VkFormatProperties p;
        vkGetPhysicalDeviceFormatProperties(physical_, f, &p);
        if (p.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) return f;
    }
    return VK_FORMAT_D16_UNORM;
}

bool VkContext::setWindow(ANativeWindow* window) {
    if (device_) vkDeviceWaitIdle(device_);
    destroySwapchain();
    if (surface_) { vkDestroySurfaceKHR(instance_, surface_, nullptr); surface_ = VK_NULL_HANDLE; }
    if (window_) { ANativeWindow_release(window_); window_ = nullptr; }
    if (!window) return true;
    ANativeWindow_acquire(window);
    window_ = window;
    VkAndroidSurfaceCreateInfoKHR info{VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR};
    info.window = window;
    auto create = (PFN_vkCreateAndroidSurfaceKHR)vkGetInstanceProcAddr(instance_, "vkCreateAndroidSurfaceKHR");
    if (!create) { LOGE("no vkCreateAndroidSurfaceKHR"); return false; }
    VK_CHECK(create(instance_, &info, nullptr, &surface_));
    VkBool32 supported = VK_FALSE;
    vkGetPhysicalDeviceSurfaceSupportKHR(physical_, queueFamily_, surface_, &supported);
    if (!supported) { LOGE("queue cannot present"); return false; }
    return createSwapchain();
}

bool VkContext::createSwapchain() {
    VkSurfaceCapabilitiesKHR caps;
    VK_CHECK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_, surface_, &caps));
    uint32_t n = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(physical_, surface_, &n, nullptr);
    std::vector<VkSurfaceFormatKHR> formats(n);
    vkGetPhysicalDeviceSurfaceFormatsKHR(physical_, surface_, &n, formats.data());
    VkSurfaceFormatKHR chosen = formats[0];
    for (auto& f : formats) {
        if ((f.format == VK_FORMAT_R8G8B8A8_SRGB || f.format == VK_FORMAT_B8G8R8A8_SRGB) && f.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) { chosen = f; break; }
    }
    colorFormat_ = chosen.format;
    extent_ = caps.currentExtent;
    if (extent_.width == 0xFFFFFFFF || extent_.width == 0 || extent_.height == 0) {
        extent_ = {(uint32_t)std::max(1, ANativeWindow_getWidth(window_)), (uint32_t)std::max(1, ANativeWindow_getHeight(window_))};
    }
    uint32_t count = std::max(caps.minImageCount + 1, 3u);
    if (caps.maxImageCount > 0) count = std::min(count, caps.maxImageCount);
    VkSwapchainCreateInfoKHR info{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    info.surface = surface_;
    info.minImageCount = count;
    info.imageFormat = colorFormat_;
    info.imageColorSpace = chosen.colorSpace;
    info.imageExtent = extent_;
    info.imageArrayLayers = 1;
    info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    // Identity: the compositor rotates the image, so the scene never has
    // to pre-rotate its projection when the phone turns.
    info.preTransform = (caps.supportedTransforms & VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR) ? VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR : caps.currentTransform;
    info.compositeAlpha = (caps.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR) ? VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR : VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
    info.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    info.clipped = VK_TRUE;
    VK_CHECK(vkCreateSwapchainKHR(device_, &info, nullptr, &swapchain_));
    vkGetSwapchainImagesKHR(device_, swapchain_, &n, nullptr);
    images_.resize(n);
    vkGetSwapchainImagesKHR(device_, swapchain_, &n, images_.data());
    views_.resize(n);
    renderDone_.resize(n);
    for (uint32_t i = 0; i < n; ++i) {
        VkImageViewCreateInfo v{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        v.image = images_[i];
        v.viewType = VK_IMAGE_VIEW_TYPE_2D;
        v.format = colorFormat_;
        v.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        VK_CHECK(vkCreateImageView(device_, &v, nullptr, &views_[i]));
        VkSemaphoreCreateInfo sem{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        VK_CHECK(vkCreateSemaphore(device_, &sem, nullptr, &renderDone_[i]));
    }
    depthFormat_ = depthFormat();
    if (renderPass_ == VK_NULL_HANDLE && !createRenderPass()) return false;

    // Multisampled colour and depth, transient where the driver allows it.
    auto attachment = [&](VkFormat format, VkImageUsageFlags usage, VkImageAspectFlags aspect, VkTexture& t) -> bool {
        VkImageCreateInfo im{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
        im.imageType = VK_IMAGE_TYPE_2D;
        im.format = format;
        im.extent = {extent_.width, extent_.height, 1};
        im.mipLevels = 1; im.arrayLayers = 1;
        im.samples = samples_;
        im.tiling = VK_IMAGE_TILING_OPTIMAL;
        im.usage = usage | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT;
        VK_CHECK(vkCreateImage(device_, &im, nullptr, &t.image));
        VkMemoryRequirements req;
        vkGetImageMemoryRequirements(device_, t.image, &req);
        uint32_t type = memoryType(req.memoryTypeBits, VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT);
        if (type == UINT32_MAX) type = memoryType(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
        alloc.allocationSize = req.size;
        alloc.memoryTypeIndex = type;
        VK_CHECK(vkAllocateMemory(device_, &alloc, nullptr, &t.memory));
        VK_CHECK(vkBindImageMemory(device_, t.image, t.memory, 0));
        VkImageViewCreateInfo v{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        v.image = t.image; v.viewType = VK_IMAGE_VIEW_TYPE_2D; v.format = format;
        v.subresourceRange = {aspect, 0, 1, 0, 1};
        VK_CHECK(vkCreateImageView(device_, &v, nullptr, &t.view));
        t.width = extent_.width; t.height = extent_.height; t.format = format;
        return true;
    };
    if (!attachment(colorFormat_, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, VK_IMAGE_ASPECT_COLOR_BIT, msaaColor_)) return false;
    if (!attachment(depthFormat_, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VK_IMAGE_ASPECT_DEPTH_BIT, depth_)) return false;
    framebuffers_.resize(n);
    for (uint32_t i = 0; i < n; ++i) {
        VkImageView attachments[3] = {msaaColor_.view, depth_.view, views_[i]};
        VkFramebufferCreateInfo fb{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
        fb.renderPass = renderPass_;
        fb.attachmentCount = 3;
        fb.pAttachments = attachments;
        fb.width = extent_.width; fb.height = extent_.height; fb.layers = 1;
        VK_CHECK(vkCreateFramebuffer(device_, &fb, nullptr, &framebuffers_[i]));
    }
    outOfDate_ = false;
    LOGI("swapchain %ux%u, %u images, format %d", extent_.width, extent_.height, n, (int)colorFormat_);
    return true;
}

void VkContext::destroySwapchain() {
    if (device_ == VK_NULL_HANDLE) return;
    vkDeviceWaitIdle(device_);
    for (VkFramebuffer f : framebuffers_) vkDestroyFramebuffer(device_, f, nullptr);
    framebuffers_.clear();
    destroyTexture(msaaColor_);
    destroyTexture(depth_);
    for (VkImageView v : views_) vkDestroyImageView(device_, v, nullptr);
    views_.clear();
    for (VkSemaphore s : renderDone_) vkDestroySemaphore(device_, s, nullptr);
    renderDone_.clear();
    images_.clear();
    if (swapchain_) { vkDestroySwapchainKHR(device_, swapchain_, nullptr); swapchain_ = VK_NULL_HANDLE; }
}

bool VkContext::createRenderPass() {
    VkAttachmentDescription attachments[3]{};
    attachments[0].format = colorFormat_;
    attachments[0].samples = samples_;
    attachments[0].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    attachments[0].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    attachments[0].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    attachments[0].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    attachments[0].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    attachments[0].finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    attachments[1].format = depthFormat_;
    attachments[1].samples = samples_;
    attachments[1].loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    attachments[1].storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    attachments[1].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    attachments[1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    attachments[1].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    attachments[1].finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    attachments[2].format = colorFormat_;
    attachments[2].samples = VK_SAMPLE_COUNT_1_BIT;
    attachments[2].loadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    attachments[2].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    attachments[2].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    attachments[2].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    attachments[2].initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    attachments[2].finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    VkAttachmentReference color{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkAttachmentReference depth{1, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};
    VkAttachmentReference resolve{2, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkSubpassDescription subpass{};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &color;
    subpass.pDepthStencilAttachment = &depth;
    subpass.pResolveAttachments = &resolve;
    VkSubpassDependency deps[2]{};
    deps[0].srcSubpass = VK_SUBPASS_EXTERNAL; deps[0].dstSubpass = 0;
    deps[0].srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    deps[0].dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    deps[0].srcAccessMask = 0;
    deps[0].dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    deps[1].srcSubpass = 0; deps[1].dstSubpass = VK_SUBPASS_EXTERNAL;
    deps[1].srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    deps[1].dstStageMask = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
    deps[1].srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    deps[1].dstAccessMask = 0;
    VkRenderPassCreateInfo info{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
    info.attachmentCount = 3;
    info.pAttachments = attachments;
    info.subpassCount = 1;
    info.pSubpasses = &subpass;
    info.dependencyCount = 2;
    info.pDependencies = deps;
    VK_CHECK(vkCreateRenderPass(device_, &info, nullptr, &renderPass_));
    return true;
}

bool VkContext::beginFrame(VkCommandBuffer& cmd, int& frameIndex) {
    if (swapchain_ == VK_NULL_HANDLE) return false;
    if (outOfDate_) { destroySwapchain(); if (!createSwapchain()) return false; }
    Frame& f = frames_[frame_];
    vkWaitForFences(device_, 1, &f.fence, VK_TRUE, UINT64_MAX);
    VkResult r = vkAcquireNextImageKHR(device_, swapchain_, UINT64_MAX, f.acquired, VK_NULL_HANDLE, &imageIndex_);
    if (r == VK_ERROR_OUT_OF_DATE_KHR) { outOfDate_ = true; return false; }
    if (r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR) { LOGE("acquire failed: %d", (int)r); return false; }
    vkResetFences(device_, 1, &f.fence);
    vkResetCommandBuffer(f.cmd, 0);
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(f.cmd, &begin);
    VkClearValue clears[3]{};
    clears[0].color = {{0, 0, 0, 1}};
    clears[1].depthStencil = {1.f, 0};
    clears[2].color = {{0, 0, 0, 1}};
    VkRenderPassBeginInfo pass{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};
    pass.renderPass = renderPass_;
    pass.framebuffer = framebuffers_[imageIndex_];
    pass.renderArea = {{0, 0}, extent_};
    pass.clearValueCount = 3;
    pass.pClearValues = clears;
    vkCmdBeginRenderPass(f.cmd, &pass, VK_SUBPASS_CONTENTS_INLINE);
    // Negative height: NDC y up, like Metal, so the scene's matrices and winding carry over.
    VkViewport viewport{0, (float)extent_.height, (float)extent_.width, -(float)extent_.height, 0, 1};
    VkRect2D scissor{{0, 0}, extent_};
    vkCmdSetViewport(f.cmd, 0, 1, &viewport);
    vkCmdSetScissor(f.cmd, 0, 1, &scissor);
    cmd = f.cmd;
    frameIndex = frame_;
    return true;
}

void VkContext::endFrame(VkCommandBuffer cmd) {
    Frame& f = frames_[frame_];
    vkCmdEndRenderPass(cmd);
    vkEndCommandBuffer(cmd);
    VkPipelineStageFlags wait = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.waitSemaphoreCount = 1;
    submit.pWaitSemaphores = &f.acquired;
    submit.pWaitDstStageMask = &wait;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &cmd;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &renderDone_[imageIndex_];
    vkQueueSubmit(queue_, 1, &submit, f.fence);
    VkPresentInfoKHR present{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    present.waitSemaphoreCount = 1;
    present.pWaitSemaphores = &renderDone_[imageIndex_];
    present.swapchainCount = 1;
    present.pSwapchains = &swapchain_;
    present.pImageIndices = &imageIndex_;
    VkResult r = vkQueuePresentKHR(queue_, &present);
    if (r == VK_ERROR_OUT_OF_DATE_KHR || r == VK_SUBOPTIMAL_KHR) outOfDate_ = true;
    frame_ = (frame_ + 1) % framesInFlight;
    frameCounter_ += 1;
}

void VkContext::waitIdle() { if (device_) vkDeviceWaitIdle(device_); }

uint32_t VkContext::memoryType(uint32_t bits, VkMemoryPropertyFlags props) const {
    for (uint32_t i = 0; i < memory_.memoryTypeCount; ++i) {
        if ((bits & (1u << i)) && (memory_.memoryTypes[i].propertyFlags & props) == props) return i;
    }
    return UINT32_MAX;
}

VkBuffer_ VkContext::createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, bool hostVisible) {
    VkBuffer_ b;
    b.size = size;
    VkBufferCreateInfo info{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    info.size = size;
    info.usage = usage;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (vkCreateBuffer(device_, &info, nullptr, &b.buffer) != VK_SUCCESS) return b;
    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(device_, b.buffer, &req);
    VkMemoryPropertyFlags props = hostVisible ? (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) : VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    uint32_t type = memoryType(req.memoryTypeBits, props);
    if (type == UINT32_MAX) type = memoryType(req.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    alloc.allocationSize = req.size;
    alloc.memoryTypeIndex = type;
    vkAllocateMemory(device_, &alloc, nullptr, &b.memory);
    vkBindBufferMemory(device_, b.buffer, b.memory, 0);
    if (hostVisible) vkMapMemory(device_, b.memory, 0, size, 0, &b.mapped);
    return b;
}

void VkContext::destroyBuffer(VkBuffer_& b) {
    if (b.mapped) vkUnmapMemory(device_, b.memory);
    if (b.buffer) vkDestroyBuffer(device_, b.buffer, nullptr);
    if (b.memory) vkFreeMemory(device_, b.memory, nullptr);
    b = VkBuffer_();
}

VkCommandBuffer VkContext::beginOneShot() {
    VkCommandBufferAllocateInfo alloc{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    alloc.commandPool = pool_;
    alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc.commandBufferCount = 1;
    VkCommandBuffer cmd;
    vkAllocateCommandBuffers(device_, &alloc, &cmd);
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &begin);
    return cmd;
}

void VkContext::endOneShot(VkCommandBuffer cmd) {
    vkEndCommandBuffer(cmd);
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &cmd;
    vkQueueSubmit(queue_, 1, &submit, VK_NULL_HANDLE);
    vkQueueWaitIdle(queue_);
    vkFreeCommandBuffers(device_, pool_, 1, &cmd);
}

VkTexture VkContext::createTexture(uint32_t w, uint32_t h, const uint8_t* rgba, bool srgb, bool mipmapped) {
    VkTexture t;
    t.width = w; t.height = h;
    t.format = srgb ? VK_FORMAT_R8G8B8A8_SRGB : VK_FORMAT_R8G8B8A8_UNORM;
    t.mips = mipmapped ? (uint32_t)std::floor(std::log2((double)std::max(w, h))) + 1 : 1;
    VkFormatProperties fp;
    vkGetPhysicalDeviceFormatProperties(physical_, t.format, &fp);
    if (!(fp.optimalTilingFeatures & VK_FORMAT_FEATURE_BLIT_SRC_BIT) || !(fp.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)) t.mips = 1;
    VkImageCreateInfo im{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    im.imageType = VK_IMAGE_TYPE_2D;
    im.format = t.format;
    im.extent = {w, h, 1};
    im.mipLevels = t.mips; im.arrayLayers = 1;
    im.samples = VK_SAMPLE_COUNT_1_BIT;
    im.tiling = VK_IMAGE_TILING_OPTIMAL;
    im.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    im.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    if (vkCreateImage(device_, &im, nullptr, &t.image) != VK_SUCCESS) return t;
    VkMemoryRequirements req;
    vkGetImageMemoryRequirements(device_, t.image, &req);
    VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    alloc.allocationSize = req.size;
    alloc.memoryTypeIndex = memoryType(req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(device_, &alloc, nullptr, &t.memory);
    vkBindImageMemory(device_, t.image, t.memory, 0);

    VkBuffer_ staging = createBuffer((VkDeviceSize)w * h * 4, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, true);
    memcpy(staging.mapped, rgba, (size_t)w * h * 4);
    VkCommandBuffer cmd = beginOneShot();
    VkImageMemoryBarrier barrier{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    barrier.image = t.image;
    barrier.srcQueueFamilyIndex = barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, t.mips, 0, 1};
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
    VkBufferImageCopy copy{};
    copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    copy.imageExtent = {w, h, 1};
    vkCmdCopyBufferToImage(cmd, staging.buffer, t.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);
    // Mip chain by blits: each level becomes the source of the next.
    int32_t mw = (int32_t)w, mh = (int32_t)h;
    for (uint32_t level = 1; level < t.mips; ++level) {
        barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, level - 1, 1, 0, 1};
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
        int32_t nw = std::max(1, mw / 2), nh = std::max(1, mh / 2);
        VkImageBlit blit{};
        blit.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level - 1, 0, 1};
        blit.srcOffsets[1] = {mw, mh, 1};
        blit.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, level, 0, 1};
        blit.dstOffsets[1] = {nw, nh, 1};
        vkCmdBlitImage(cmd, t.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, t.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
        mw = nw; mh = nh;
    }
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, t.mips - 1, 1, 0, 1};
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
    endOneShot(cmd);
    destroyBuffer(staging);

    VkImageViewCreateInfo v{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    v.image = t.image; v.viewType = VK_IMAGE_VIEW_TYPE_2D; v.format = t.format;
    v.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, t.mips, 0, 1};
    vkCreateImageView(device_, &v, nullptr, &t.view);
    return t;
}

void VkContext::destroyTexture(VkTexture& t) {
    if (t.view) vkDestroyImageView(device_, t.view, nullptr);
    if (t.image) vkDestroyImage(device_, t.image, nullptr);
    if (t.memory) vkFreeMemory(device_, t.memory, nullptr);
    t = VkTexture();
}

VkShaderModule VkContext::loadShader(const std::string& assetPath) {
    AAsset* asset = AAssetManager_open(assets_, assetPath.c_str(), AASSET_MODE_BUFFER);
    if (!asset) { LOGE("missing shader %s", assetPath.c_str()); return VK_NULL_HANDLE; }
    size_t size = (size_t)AAsset_getLength(asset);
    std::vector<uint32_t> words((size + 3) / 4);
    AAsset_read(asset, words.data(), size);
    AAsset_close(asset);
    VkShaderModuleCreateInfo info{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    info.codeSize = size;
    info.pCode = words.data();
    VkShaderModule module = VK_NULL_HANDLE;
    if (vkCreateShaderModule(device_, &info, nullptr, &module) != VK_SUCCESS) LOGE("bad shader %s", assetPath.c_str());
    return module;
}

} // namespace ck
