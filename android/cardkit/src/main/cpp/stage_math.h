// Vectors, matrices, easings, springs and noise of the stage: a direct
// port of StageMath.swift so both platforms compute the same frames.
#pragma once
#include <cmath>
#include <cstdint>
#include <algorithm>

namespace ck {

struct vec2 { float x = 0, y = 0;
    vec2() = default; vec2(float a, float b) : x(a), y(b) {}
    vec2 operator+(vec2 o) const { return {x + o.x, y + o.y}; }
    vec2 operator-(vec2 o) const { return {x - o.x, y - o.y}; }
    vec2 operator*(float s) const { return {x * s, y * s}; }
    vec2 operator/(float s) const { return {x / s, y / s}; }
    vec2& operator+=(vec2 o) { x += o.x; y += o.y; return *this; }
    float operator[](int i) const { return i == 0 ? x : y; }
};
struct vec3 { float x = 0, y = 0, z = 0;
    vec3() = default; vec3(float a, float b, float c) : x(a), y(b), z(c) {}
    explicit vec3(float s) : x(s), y(s), z(s) {}
    vec3 operator+(vec3 o) const { return {x + o.x, y + o.y, z + o.z}; }
    vec3 operator-(vec3 o) const { return {x - o.x, y - o.y, z - o.z}; }
    vec3 operator-() const { return {-x, -y, -z}; }
    vec3 operator*(float s) const { return {x * s, y * s, z * s}; }
    vec3 operator*(vec3 o) const { return {x * o.x, y * o.y, z * o.z}; }
    vec3 operator/(float s) const { return {x / s, y / s, z / s}; }
    vec3& operator+=(vec3 o) { x += o.x; y += o.y; z += o.z; return *this; }
    vec3& operator-=(vec3 o) { x -= o.x; y -= o.y; z -= o.z; return *this; }
    vec3& operator*=(float s) { x *= s; y *= s; z *= s; return *this; }
    float operator[](int i) const { return i == 0 ? x : i == 1 ? y : z; }
    float& operator[](int i) { return i == 0 ? x : i == 1 ? y : z; }
};
struct vec4 { float x = 0, y = 0, z = 0, w = 0;
    vec4() = default; vec4(float a, float b, float c, float d) : x(a), y(b), z(c), w(d) {}
    vec4(vec3 v, float d) : x(v.x), y(v.y), z(v.z), w(d) {}
    vec3 xyz() const { return {x, y, z}; }
};

inline float dot(vec3 a, vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline vec3 cross(vec3 a, vec3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
inline float length(vec3 a) { return std::sqrt(dot(a, a)); }
inline float length(vec2 a) { return std::sqrt(a.x * a.x + a.y * a.y); }
inline vec3 normalize(vec3 a) { float l = length(a); return l > 0 ? a / l : vec3(0, 0, 1); }
inline vec3 mix(vec3 a, vec3 b, float t) { return a + (b - a) * t; }
inline float clamp01(float x) { return std::min(1.0f, std::max(0.0f, x)); }
inline float clampf(float x, float a, float b) { return std::min(b, std::max(a, x)); }
inline float lerp(float a, float b, float t) { return a + (b - a) * t; }
inline float progress(float x, float a, float b) { return clamp01((x - a) / (b - a)); }
inline float smoothstep(float a, float b, float x) { float t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); }
inline float wrapf(float x, float m) { return std::fmod(std::fmod(x, m) + m, m); }
inline float roundf_(float x) { return std::round(x); }

/// Column-major 4×4, like simd's float4x4: columns[c][r].
struct mat4 {
    vec4 c[4];
    mat4() { c[0] = {1, 0, 0, 0}; c[1] = {0, 1, 0, 0}; c[2] = {0, 0, 1, 0}; c[3] = {0, 0, 0, 1}; }
    static mat4 columns(vec4 a, vec4 b, vec4 d, vec4 e) { mat4 m; m.c[0] = a; m.c[1] = b; m.c[2] = d; m.c[3] = e; return m; }
    float at(int row, int col) const { const vec4& v = c[col]; return row == 0 ? v.x : row == 1 ? v.y : row == 2 ? v.z : v.w; }
    float& at(int row, int col) { vec4& v = c[col]; return row == 0 ? v.x : row == 1 ? v.y : row == 2 ? v.z : v.w; }
    vec4 operator*(vec4 v) const {
        return {
            c[0].x * v.x + c[1].x * v.y + c[2].x * v.z + c[3].x * v.w,
            c[0].y * v.x + c[1].y * v.y + c[2].y * v.z + c[3].y * v.w,
            c[0].z * v.x + c[1].z * v.y + c[2].z * v.z + c[3].z * v.w,
            c[0].w * v.x + c[1].w * v.y + c[2].w * v.z + c[3].w * v.w,
        };
    }
    mat4 operator*(const mat4& o) const { mat4 r; for (int i = 0; i < 4; ++i) r.c[i] = (*this) * o.c[i]; return r; }
    mat4 transposed() const { mat4 r; for (int i = 0; i < 4; ++i) for (int j = 0; j < 4; ++j) r.at(i, j) = at(j, i); return r; }
    mat4 inverse() const;
};

inline mat4 translation(vec3 t) { mat4 m; m.c[3] = {t.x, t.y, t.z, 1}; return m; }
inline mat4 scale(vec3 s) { mat4 m; m.c[0].x = s.x; m.c[1].y = s.y; m.c[2].z = s.z; return m; }
inline mat4 rotationX(float a) { float c_ = std::cos(a), s = std::sin(a); return mat4::columns({1, 0, 0, 0}, {0, c_, s, 0}, {0, -s, c_, 0}, {0, 0, 0, 1}); }
inline mat4 rotationY(float a) { float c_ = std::cos(a), s = std::sin(a); return mat4::columns({c_, 0, -s, 0}, {0, 1, 0, 0}, {s, 0, c_, 0}, {0, 0, 0, 1}); }
inline mat4 rotationZ(float a) { float c_ = std::cos(a), s = std::sin(a); return mat4::columns({c_, s, 0, 0}, {-s, c_, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}); }
/// Euler rotation in the YXZ order (yaw, then pitch, then roll).
inline mat4 rotationYXZ(float x, float y, float z) { return rotationY(y) * rotationX(x) * rotationZ(z); }
inline mat4 model(vec3 position, vec3 euler, float s) { return translation(position) * rotationYXZ(euler.x, euler.y, euler.z) * scale(vec3(s)); }
inline mat4 mirrorY(float y) { return translation({0, 2 * y, 0}) * scale({1, -1, 1}); }

inline mat4 perspective(float fovY, float aspect, float near_, float far_) {
    float y = 1 / std::tan(fovY / 2), x = y / aspect, z = far_ / (near_ - far_);
    return mat4::columns({x, 0, 0, 0}, {0, y, 0, 0}, {0, 0, z, -1}, {0, 0, z * near_, 0});
}
inline mat4 lookAt(vec3 eye, vec3 target, vec3 up = {0, 1, 0}) {
    vec3 f = normalize(target - eye), s = normalize(cross(f, up)), u = cross(s, f);
    return mat4::columns({s.x, u.x, -f.x, 0}, {s.y, u.y, -f.y, 0}, {s.z, u.z, -f.z, 0}, {-dot(s, eye), -dot(u, eye), dot(f, eye), 1});
}

inline mat4 mat4::inverse() const {
    // Gauss-Jordan on a 4×4; the stage only inverts well-conditioned models and projections.
    float a[4][8];
    for (int r = 0; r < 4; ++r) { for (int cc = 0; cc < 4; ++cc) { a[r][cc] = at(r, cc); a[r][cc + 4] = (r == cc) ? 1.f : 0.f; } }
    for (int col = 0; col < 4; ++col) {
        int pivot = col;
        for (int r = col + 1; r < 4; ++r) if (std::fabs(a[r][col]) > std::fabs(a[pivot][col])) pivot = r;
        if (pivot != col) for (int k = 0; k < 8; ++k) std::swap(a[col][k], a[pivot][k]);
        float p = a[col][col]; if (std::fabs(p) < 1e-12f) return mat4();
        for (int k = 0; k < 8; ++k) a[col][k] /= p;
        for (int r = 0; r < 4; ++r) if (r != col) { float f = a[r][col]; if (f != 0) for (int k = 0; k < 8; ++k) a[r][k] -= f * a[col][k]; }
    }
    mat4 m; for (int r = 0; r < 4; ++r) for (int cc = 0; cc < 4; ++cc) m.at(r, cc) = a[r][cc + 4];
    return m;
}

/// Unit quaternion (x, y, z, w), like simd_quatf.
struct quat { float x = 0, y = 0, z = 0, w = 1;
    static quat axisAngle(float angle, vec3 axis) { float s = std::sin(angle / 2); vec3 n = normalize(axis); return {n.x * s, n.y * s, n.z * s, std::cos(angle / 2)}; }
    quat operator*(const quat& o) const {
        return { w * o.x + x * o.w + y * o.z - z * o.y,
                 w * o.y - x * o.z + y * o.w + z * o.x,
                 w * o.z + x * o.y - y * o.x + z * o.w,
                 w * o.w - x * o.x - y * o.y - z * o.z };
    }
    vec3 act(vec3 v) const { vec3 u{x, y, z}; vec3 t = cross(u, v) * 2.f; return v + t * w + cross(u, t); }
    mat4 matrix() const {
        float xx = x * x, yy = y * y, zz = z * z, xy = x * y, xz = x * z, yz = y * z, wx = w * x, wy = w * y, wz = w * z;
        return mat4::columns({1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0},
                             {2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0},
                             {2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0},
                             {0, 0, 0, 1});
    }
    /// From the rotation part of a matrix (orthonormal columns).
    static quat fromMatrix(const mat4& m) {
        float m00 = m.at(0,0), m11 = m.at(1,1), m22 = m.at(2,2);
        float tr = m00 + m11 + m22; quat q;
        if (tr > 0) { float s = std::sqrt(tr + 1) * 2; q.w = 0.25f * s; q.x = (m.at(2,1) - m.at(1,2)) / s; q.y = (m.at(0,2) - m.at(2,0)) / s; q.z = (m.at(1,0) - m.at(0,1)) / s; }
        else if (m00 > m11 && m00 > m22) { float s = std::sqrt(1 + m00 - m11 - m22) * 2; q.w = (m.at(2,1) - m.at(1,2)) / s; q.x = 0.25f * s; q.y = (m.at(0,1) + m.at(1,0)) / s; q.z = (m.at(0,2) + m.at(2,0)) / s; }
        else if (m11 > m22) { float s = std::sqrt(1 + m11 - m00 - m22) * 2; q.w = (m.at(0,2) - m.at(2,0)) / s; q.x = (m.at(0,1) + m.at(1,0)) / s; q.y = 0.25f * s; q.z = (m.at(1,2) + m.at(2,1)) / s; }
        else { float s = std::sqrt(1 + m22 - m00 - m11) * 2; q.w = (m.at(1,0) - m.at(0,1)) / s; q.x = (m.at(0,2) + m.at(2,0)) / s; q.y = (m.at(1,2) + m.at(2,1)) / s; q.z = 0.25f * s; }
        return q;
    }
};
inline quat slerp(quat a, quat b, float t) {
    float d = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    if (d < 0) { b = {-b.x, -b.y, -b.z, -b.w}; d = -d; }
    if (d > 0.9995f) { quat r{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t}; float l = std::sqrt(r.x*r.x + r.y*r.y + r.z*r.z + r.w*r.w); return {r.x / l, r.y / l, r.z / l, r.w / l}; }
    float th = std::acos(d), s = std::sin(th), wa = std::sin((1 - t) * th) / s, wb = std::sin(t * th) / s;
    return {a.x * wa + b.x * wb, a.y * wa + b.y * wb, a.z * wa + b.z * wb, a.w * wa + b.w * wb};
}
/// YXZ euler to quaternion, like StageScene.quaternion(euler:).
inline quat quatEuler(vec3 e) { return quat::axisAngle(e.y, {0, 1, 0}) * quat::axisAngle(e.x, {1, 0, 0}) * quat::axisAngle(e.z, {0, 0, 1}); }

/// Easing curves of the choreography.
namespace ease {
inline float smooth(float t) { t = clamp01(t); return t < 0.5f ? 4 * t * t * t : 1 - std::pow(-2 * t + 2, 3.f) / 2; }
inline float outCubic(float t) { return 1 - std::pow(1 - clamp01(t), 3.f); }
inline float inCubic(float t) { return std::pow(clamp01(t), 3.f); }
inline float backOut(float t) { t = clamp01(t); const float c = 1.70158f; return 1 + (c + 1) * std::pow(t - 1, 3.f) + c * std::pow(t - 1, 2.f); }
}

/// Critically damped spring step.
inline void springStep(float& x, float& v, float target, float k, float dt) {
    float damping = 2 * std::sqrt(k);
    v += (k * (target - x) - damping * v) * dt;
    x += v * dt;
}

/// Deterministic value noise shared by the geometry and the normal map.
namespace noise {
inline float hash(int32_t x, int32_t y, int32_t seed) {
    uint32_t n = (uint32_t)x * 374761393u + (uint32_t)y * 668265263u + (uint32_t)seed * 1442695041u;
    n = (n ^ (n >> 13)) * 1274126177u;
    n = n ^ (n >> 16);
    return (float)n / 4294967296.f;
}
inline float value(float x, float y, int32_t seed = 0) {
    float fx = std::floor(x), fy = std::floor(y);
    int32_t ix = (int32_t)fx, iy = (int32_t)fy;
    float rx = x - fx, ry = y - fy;
    float ox = rx * rx * (3 - 2 * rx), oy = ry * ry * (3 - 2 * ry);
    float c = hash(ix, iy, seed), h = hash(ix + 1, iy, seed), f = hash(ix, iy + 1, seed), u = hash(ix + 1, iy + 1, seed);
    return (c + (h - c) * ox + (f - c) * oy + (c - h - f + u) * ox * oy) * 2 - 1;
}
inline float fbm(float x, float y, int32_t seed = 0, int octaves = 4) {
    float sum = 0, amp = 0.5f, norm = 0, px = x, py = y;
    for (int o = 0; o < octaves; ++o) { sum += amp * value(px, py, seed + o * 17); norm += amp; px = px * 2.03f + 11.7f; py = py * 2.03f + 3.1f; amp *= 0.5f; }
    return sum / norm;
}
/// Small deterministic generator for the long creases and the ray wedges.
struct Generator {
    uint32_t state;
    explicit Generator(uint32_t seed) : state(seed) {}
    float next() {
        state += 1831565813u;
        uint32_t t = state;
        t = (t ^ (t >> 15)) * (t | 1u);
        t ^= t + (t ^ (t >> 7)) * (t | 61u);
        return (float)(t ^ (t >> 14)) / 4294967296.f;
    }
};
}

/// Uniform random in [0, 1), for particles (not deterministic, like the reference).
inline float frand() { return (float)std::rand() / ((float)RAND_MAX + 1.f); }
inline float frand(float a, float b) { return a + frand() * (b - a); }

} // namespace ck
