// The bridge to Kotlin: one native Stage owns the Vulkan context, the
// scene and the renderer on its own render thread. Everything from the
// UI thread is queued and applied between frames; the scene's callbacks
// go back through the StageCallbacks object.
#include <jni.h>
#include <android/native_window_jni.h>
#include <android/asset_manager_jni.h>
#include <android/log.h>
#include <atomic>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>
#include "stage_scene.h"
#include "stage_renderer.h"
#include "vk_context.h"

#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "CardStage", __VA_ARGS__)

namespace {

JavaVM* gVM = nullptr;

struct Stage {
    AAssetManager* assets = nullptr;
    jobject callbacks = nullptr;
    jmethodID onPhase = nullptr, onHint = nullptr, onOpened = nullptr;
    ck::StageSettings settings;
    std::unique_ptr<ck::StageScene> scene;
    std::unique_ptr<ck::VkContext> vk;
    std::unique_ptr<ck::StageRenderer> renderer;
    std::thread thread;
    std::atomic<bool> running{true};
    std::mutex mutex;
    std::vector<std::function<void()>> queue;
    float density = 1;
    bool ready = false;

    void post(std::function<void()> fn) { std::lock_guard<std::mutex> lock(mutex); queue.push_back(std::move(fn)); }
    void postAndWait(std::function<void()> fn) {
        std::promise<void> done;
        auto future = done.get_future();
        post([&]() { fn(); done.set_value(); });
        future.wait();
    }
    void drain() {
        std::vector<std::function<void()>> pending;
        { std::lock_guard<std::mutex> lock(mutex); pending.swap(queue); }
        for (auto& fn : pending) fn();
    }
    void loop() {
        JNIEnv* env = nullptr;
        gVM->AttachCurrentThread(&env, nullptr);
        vk = std::make_unique<ck::VkContext>();
        if (vk->init(assets)) {
            scene = std::make_unique<ck::StageScene>(settings);
            scene->onPhase = [this, env](ck::Phase p) { if (callbacks) env->CallVoidMethod(callbacks, onPhase, (jint)p); };
            scene->onHint = [this, env](const std::string& s) {
                if (!callbacks) return;
                jstring js = env->NewStringUTF(s.c_str());
                env->CallVoidMethod(callbacks, onHint, js);
                env->DeleteLocalRef(js);
            };
            scene->onOpenRequest = [this, env](int index) {
                if (!renderer || renderer->preparedCount() == 0) return false;
                int n = renderer->preparedCount();
                if (!scene->open(index, n)) return false;
                renderer->dealPrepared();
                if (callbacks) env->CallVoidMethod(callbacks, onOpened, (jint)index);
                return true;
            };
            ready = true;
        } else {
            LOGE("Vulkan unavailable");
        }
        while (running) {
            drain();
            if (ready && renderer && vk->hasSwapchain()) {
                renderer->render();
            } else {
                std::this_thread::sleep_for(std::chrono::milliseconds(16));
            }
        }
        drain();
        renderer.reset();
        if (vk) { vk->setWindow(nullptr); vk->destroy(); }
        vk.reset();
        scene.reset();
        if (callbacks) { env->DeleteGlobalRef(callbacks); callbacks = nullptr; }
        gVM->DetachCurrentThread();
    }
};

Stage* stage(jlong handle) { return reinterpret_cast<Stage*>(handle); }

ck::Pixels pixels(JNIEnv* env, jobject buffer, jint w, jint h) {
    ck::Pixels p;
    if (!buffer || w <= 0 || h <= 0) return p;
    uint8_t* data = (uint8_t*)env->GetDirectBufferAddress(buffer);
    jlong cap = env->GetDirectBufferCapacity(buffer);
    if (!data || cap < (jlong)w * h * 4) return p;
    p.width = (uint32_t)w; p.height = (uint32_t)h;
    p.rgba.assign(data, data + (size_t)w * h * 4);
    return p;
}

std::string str(JNIEnv* env, jstring s) {
    if (!s) return {};
    const char* c = env->GetStringUTFChars(s, nullptr);
    std::string out = c ? c : "";
    env->ReleaseStringUTFChars(s, c);
    return out;
}

} // namespace

extern "C" {

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*) { gVM = vm; return JNI_VERSION_1_6; }

#define STAGE(name) JNIEXPORT JNICALL Java_com_amazingcards_cardkit_stage_StageNative_##name

jlong STAGE(create)(JNIEnv* env, jclass, jobject assetManager, jobject callbacks, jfloat density) {
    Stage* s = new Stage();
    s->assets = AAssetManager_fromJava(env, assetManager);
    s->density = density;
    s->callbacks = env->NewGlobalRef(callbacks);
    jclass cls = env->GetObjectClass(callbacks);
    s->onPhase = env->GetMethodID(cls, "onPhase", "(I)V");
    s->onHint = env->GetMethodID(cls, "onHint", "(Ljava/lang/String;)V");
    s->onOpened = env->GetMethodID(cls, "onOpened", "(I)V");
    s->thread = std::thread([s]() { s->loop(); });
    return reinterpret_cast<jlong>(s);
}

void STAGE(destroy)(JNIEnv*, jclass, jlong handle) {
    Stage* s = stage(handle);
    if (!s) return;
    s->running = false;
    if (s->thread.joinable()) s->thread.join();
    delete s;
}

void STAGE(setSurface)(JNIEnv* env, jclass, jlong handle, jobject surface) {
    Stage* s = stage(handle);
    ANativeWindow* window = surface ? ANativeWindow_fromSurface(env, surface) : nullptr;
    s->postAndWait([s, window]() {
        if (!s->vk) { if (window) ANativeWindow_release(window); return; }
        if (window) {
            if (s->vk->setWindow(window) && !s->renderer) {
                s->renderer = std::make_unique<ck::StageRenderer>(*s->vk, *s->scene);
                if (!s->renderer->init()) { LOGE("renderer init failed"); s->renderer.reset(); }
            }
            ANativeWindow_release(window);
        } else {
            s->vk->setWindow(nullptr);
        }
    });
}

void STAGE(resize)(JNIEnv*, jclass, jlong handle, jint width, jint height, jfloat density) {
    Stage* s = stage(handle);
    s->post([s, width, height, density]() {
        s->density = density;
        if (s->scene) s->scene->resize((float)width / density, (float)height / density);
        if (s->vk) s->vk->invalidate();
    });
}

void STAGE(setSettings)(JNIEnv* env, jclass, jlong handle, jfloatArray values) {
    Stage* s = stage(handle);
    jfloat v[26] = {0};
    jsize n = std::min<jsize>(26, env->GetArrayLength(values));
    env->GetFloatArrayRegion(values, 0, n, v);
    ck::StageSettings st;
    st.packs = (int)v[0]; st.spacing = v[1]; st.depth = v[2]; st.fov = v[3]; st.tilt = v[4]; st.floats = v[5] > 0.5f;
    st.reflection = v[6]; st.shadow = v[7]; st.lighting = v[8] > 0.5f ? ck::Lighting::night : ck::Lighting::studio; st.background = v[9] > 0.5f;
    st.puff = v[10]; st.wrinkles = v[11]; st.foil = v[12]; st.holo = v[13]; st.gloss = v[14]; st.shine = v[15];
    st.opening = (ck::Opening)std::clamp((int)v[16], 0, 5); st.speed = v[17]; st.hold = v[18]; st.autoOpen = v[19];
    st.rareLast = v[20] > 0.5f; st.guide = v[21] > 0.5f; st.hints = v[22] > 0.5f; st.particles = v[23]; st.rays = v[24] > 0.5f;
    s->post([s, st]() { s->settings = st; if (s->scene) s->scene->setSettings(st); });
}

void STAGE(setSkin)(JNIEnv* env, jclass, jlong handle, jint index, jstring id, jint w, jint h, jobject front, jobject back, jint mw, jint mh, jobject frontMask, jobject backMask) {
    Stage* s = stage(handle);
    auto skin = std::make_shared<ck::SkinPixels>();
    skin->id = str(env, id);
    skin->front = pixels(env, front, w, h);
    skin->back = pixels(env, back, w, h);
    skin->frontMask = pixels(env, frontMask, mw, mh);
    skin->backMask = pixels(env, backMask, mw, mh);
    s->post([s, index, skin]() { if (s->renderer) s->renderer->setSkin(index, skin->front.empty() ? nullptr : skin.get()); });
}

void STAGE(prepareCards)(JNIEnv* env, jclass, jlong handle, jobjectArray ids, jint w, jint h, jobject fronts, jobject backs, jint mw, jint mh, jobject masks) {
    Stage* s = stage(handle);
    int count = ids ? env->GetArrayLength(ids) : 0;
    auto cards = std::make_shared<std::vector<ck::CardPixels>>();
    uint8_t* frontData = fronts ? (uint8_t*)env->GetDirectBufferAddress(fronts) : nullptr;
    uint8_t* backData = backs ? (uint8_t*)env->GetDirectBufferAddress(backs) : nullptr;
    uint8_t* maskData = masks ? (uint8_t*)env->GetDirectBufferAddress(masks) : nullptr;
    size_t stride = (size_t)w * h * 4, maskStride = (size_t)mw * mh * 4;
    for (int i = 0; i < count; ++i) {
        ck::CardPixels c;
        jstring js = (jstring)env->GetObjectArrayElement(ids, i);
        c.id = str(env, js);
        env->DeleteLocalRef(js);
        if (frontData) { c.front.width = w; c.front.height = h; c.front.rgba.assign(frontData + i * stride, frontData + (i + 1) * stride); }
        if (backData) { c.back.width = w; c.back.height = h; c.back.rgba.assign(backData + i * stride, backData + (i + 1) * stride); }
        if (maskData && mw > 0) { c.mask.width = mw; c.mask.height = mh; c.mask.rgba.assign(maskData + i * maskStride, maskData + (i + 1) * maskStride); }
        cards->push_back(std::move(c));
    }
    s->post([s, cards]() { if (s->renderer) s->renderer->prepareCards(*cards); });
}

void STAGE(pointer)(JNIEnv*, jclass, jlong handle, jboolean active, jfloat x, jfloat y) {
    Stage* s = stage(handle);
    s->post([s, active, x, y]() { if (s->scene) s->scene->pointerMoved(active, x / s->density, y / s->density); });
}

void STAGE(tilt)(JNIEnv*, jclass, jlong handle, jfloat x, jfloat y) {
    Stage* s = stage(handle);
    s->post([s, x, y]() { if (s->scene) s->scene->setDeviceTilt(x, y); });
}

void STAGE(dragBegan)(JNIEnv*, jclass, jlong handle, jfloat x, jfloat y, jdouble t) {
    Stage* s = stage(handle);
    s->post([s, x, y, t]() { if (s->scene) s->scene->dragBegan(x / s->density, y / s->density, t); });
}

void STAGE(dragChanged)(JNIEnv*, jclass, jlong handle, jfloat x, jfloat y, jdouble t) {
    Stage* s = stage(handle);
    s->post([s, x, y, t]() { if (s->scene) s->scene->dragChanged(x / s->density, y / s->density, t); });
}

void STAGE(dragEnded)(JNIEnv*, jclass, jlong handle, jfloat x, jfloat y, jdouble t) {
    Stage* s = stage(handle);
    s->post([s, x, y, t]() { if (s->scene) s->scene->dragEnded(x / s->density, y / s->density, t); });
}

void STAGE(open)(JNIEnv*, jclass, jlong handle) {
    Stage* s = stage(handle);
    s->post([s]() { if (s->scene && s->scene->onOpenRequest) s->scene->onOpenRequest(s->scene->frontIndex()); });
}

void STAGE(exit)(JNIEnv*, jclass, jlong handle) {
    Stage* s = stage(handle);
    s->post([s]() { if (s->scene) s->scene->exit(); });
}

void STAGE(bringToFront)(JNIEnv*, jclass, jlong handle, jint index) {
    Stage* s = stage(handle);
    s->post([s, index]() { if (s->scene) s->scene->bringToFront(index); });
}

} // extern "C"
