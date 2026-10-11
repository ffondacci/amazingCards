#include "pouch_geometry.h"
#include "stage_settings.h"
#include <cmath>

namespace ck {

static constexpr int kColumns = 150;
static constexpr int kRows = 280;

PouchMesh PouchMesh::make(bool back, int32_t seed, float puff, float wrinkles) {
    const float w = pouch::width, h = pouch::height, sealV = pouch::seal;
    const float puffAmp = 0.02f + 0.14f * puff;
    const float wrinkleAmp = 0.0078f * wrinkles;
    const float shoulder = 0.15f;
    const int cols = kColumns, rows = kRows;
    PouchMesh mesh;
    mesh.vertices.reserve((cols + 1) * (rows + 1));
    auto rise = [](float m) { return m <= 0 ? 0.f : m >= 1 ? 1.f : 1 - std::pow(1 - m, 2.4f); };
    // sin(pi) is a hair negative in float: clamp before the fractional power or the whole mesh is NaN.
    auto pleat = [](float m) { return m <= 0 ? 0.f : std::pow(std::max(0.f, std::sin((float)M_PI * std::min(1.f, m / 1.3f))), 1.4f); };
    const float tau = (float)M_PI * 2;
    for (int r = 0; r <= rows; ++r) {
        float t = (float)r / rows;
        for (int c = 0; c <= cols; ++c) {
            float p = (float)c / cols;
            // Columns bunch toward the sides, where the foil folds.
            float cx = lerp(p, 0.5f - 0.5f * std::cos((float)M_PI * p), 0.5f);
            float f = std::fabs(2 * cx - 1);
            float across = std::pow(std::max(0.f, 1 - std::pow(f, 3.6f)), 0.5f);
            float span = shoulder * (1 + 1.1f * f * f);
            float fromBottom = (t - sealV) / span;
            float fromTop = (1 - t - sealV) / span;
            float along = std::min(1.f, (std::fabs(2 * t - 1) / (1 - 2 * sealV)) * (1 + 0.1f * f * f));
            float pillow = std::pow(std::max(0.f, 1 - std::pow(along, 3.f)), 0.75f) * rise(fromBottom * 1.6f) * rise(fromTop * 1.6f);
            float bulge = puffAmp * across * pillow * (1 + 0.08f * noise::fbm(cx * 2.3f, t * 3.2f, seed, 3));
            auto folds = [&](int32_t s) {
                float n = noise::fbm(cx * 3.5f, t * 5, s, 2);
                return 0.55f * std::sin(tau * (cx * 9 + n * 0.9f)) + 0.3f * std::sin(tau * (cx * 17 + n * 1.3f + 0.3f)) + 0.15f * std::sin(tau * (cx * 29 + n * 2));
            };
            float crease = wrinkleAmp * across * (pleat(fromBottom) * folds(seed + 5) + pleat(fromTop) * folds(seed + 9));
            float edgeX = std::min(cx, 1 - cx);
            float edgeY = std::min(t, 1 - t) - sealV;
            if (edgeX < 0.3f && edgeY > 0 && edgeY < 0.3f) {
                crease += wrinkleAmp * 0.5f * across * std::sin(tau * (edgeX + edgeY) * 7) * (1 - edgeX / 0.3f) * (1 - edgeY / 0.3f);
            }
            float z = bulge + std::max(crease, -0.7f * bulge);
            if (back) {
                // Longitudinal seam of the back.
                z += 0.0034f * (1 - smoothstep(0.036f, 0.043f, std::fabs(cx - 0.5f))) * smoothstep(-0.004f, 0.02f, edgeY);
            }
            float x = (cx - 0.5f) * w * (1 - 0.062f * pillow * (0.72f + 0.28f * std::sin((float)M_PI * t)));
            float y = (t - 0.5f) * h;
            PouchVertex v; v.position = {x, y, z}; v.normal = {0, 0, 1}; v.uv = {cx, t};
            mesh.vertices.push_back(v);
        }
    }
    mesh.indices.reserve(cols * rows * 6);
    for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < cols; ++c) {
            uint32_t a = (uint32_t)(r * (cols + 1) + c), b = a + 1, d = a + (uint32_t)(cols + 1), e = d + 1;
            mesh.indices.insert(mesh.indices.end(), {a, b, e, a, e, d});
        }
    }
    mesh.computeNormals();
    return mesh;
}

void PouchMesh::computeNormals() {
    std::vector<vec3> sums(vertices.size(), vec3(0));
    for (size_t i = 0; i + 2 < indices.size(); i += 3) {
        uint32_t a = indices[i], b = indices[i + 1], c = indices[i + 2];
        vec3 n = cross(vertices[b].position - vertices[a].position, vertices[c].position - vertices[a].position);
        sums[a] += n; sums[b] += n; sums[c] += n;
    }
    for (size_t v = 0; v < vertices.size(); ++v) {
        vec3 s = sums[v];
        vertices[v].normal = length(s) > 0 ? normalize(s) : vec3(0, 0, 1);
    }
}

PouchMesh PouchMesh::card(float aspect) {
    const float w = 0.8f, h = w / aspect, r = 0.042f;
    std::vector<vec2> outline;
    const vec2 centers[4] = {{w / 2 - r, h / 2 - r}, {-w / 2 + r, h / 2 - r}, {-w / 2 + r, -h / 2 + r}, {w / 2 - r, -h / 2 + r}};
    const float starts[4] = {0, (float)M_PI / 2, (float)M_PI, 3 * (float)M_PI / 2};
    for (int ci = 0; ci < 4; ++ci) for (int k = 0; k <= 6; ++k) {
        float a = starts[ci] + (float)k / 6 * ((float)M_PI / 2);
        outline.push_back(centers[ci] + vec2(std::cos(a), std::sin(a)) * r);
    }
    PouchMesh mesh;
    PouchVertex centre; centre.position = {0, 0, 0}; centre.normal = {0, 0, 1}; centre.uv = {0.5f, 0.5f};
    mesh.vertices.push_back(centre);
    for (vec2 p : outline) { PouchVertex v; v.position = {p.x, p.y, 0}; v.normal = {0, 0, 1}; v.uv = {p.x / w + 0.5f, p.y / h + 0.5f}; mesh.vertices.push_back(v); }
    uint32_t n = (uint32_t)outline.size();
    for (uint32_t i = 0; i < n; ++i) mesh.indices.insert(mesh.indices.end(), {0u, 1 + i, 1 + (i + 1) % n});
    return mesh;
}

PouchMesh PouchMesh::slab(float w, float h, float d, float r) {
    std::vector<vec2> outline;
    const vec2 centers[4] = {{w / 2 - r, h / 2 - r}, {-w / 2 + r, h / 2 - r}, {-w / 2 + r, -h / 2 + r}, {w / 2 - r, -h / 2 + r}};
    const float starts[4] = {0, (float)M_PI / 2, (float)M_PI, 3 * (float)M_PI / 2};
    for (int ci = 0; ci < 4; ++ci) for (int k = 0; k <= 4; ++k) {
        float a = starts[ci] + (float)k / 4 * ((float)M_PI / 2);
        outline.push_back(centers[ci] + vec2(std::cos(a), std::sin(a)) * r);
    }
    PouchMesh mesh;
    uint32_t n = (uint32_t)outline.size();
    for (int face = 0; face < 2; ++face) {
        float z = face == 0 ? d / 2 : -d / 2;
        vec3 normal = face == 0 ? vec3(0, 0, 1) : vec3(0, 0, -1);
        uint32_t base = (uint32_t)mesh.vertices.size();
        PouchVertex c; c.position = {0, 0, z}; c.normal = normal; c.uv = {0.5f, 0.5f};
        mesh.vertices.push_back(c);
        for (vec2 p : outline) { PouchVertex v; v.position = {p.x, p.y, z}; v.normal = normal; v.uv = {p.x / w + 0.5f, 0.5f - p.y / h}; mesh.vertices.push_back(v); }
        for (uint32_t i = 0; i < n; ++i) {
            uint32_t a = base + 1 + i, b = base + 1 + (i + 1) % n;
            if (normal.z > 0) mesh.indices.insert(mesh.indices.end(), {base, a, b}); else mesh.indices.insert(mesh.indices.end(), {base, b, a});
        }
    }
    for (uint32_t i = 0; i < n; ++i) {
        vec2 p0 = outline[i], p1 = outline[(i + 1) % n];
        vec2 edge = p1 - p0;
        vec3 normal = normalize(vec3(edge.y, -edge.x, 0));
        uint32_t base = (uint32_t)mesh.vertices.size();
        PouchVertex v; v.normal = normal; v.uv = {0.5f, 0.5f};
        v.position = {p0.x, p0.y, d / 2}; mesh.vertices.push_back(v);
        v.position = {p1.x, p1.y, d / 2}; mesh.vertices.push_back(v);
        v.position = {p1.x, p1.y, -d / 2}; mesh.vertices.push_back(v);
        v.position = {p0.x, p0.y, -d / 2}; mesh.vertices.push_back(v);
        mesh.indices.insert(mesh.indices.end(), {base, base + 1, base + 2, base, base + 2, base + 3});
    }
    return mesh;
}

WrinkleNormalMap WrinkleNormalMap::make() {
    const int w = width, h = height;
    const float sealV = pouch::seal;
    const float dx = pouch::width / (float)(w - 1);
    const float dy = pouch::height / (float)(h - 1);
    std::vector<float> field((size_t)w * h, 0.f);
    const float tau = (float)M_PI * 2;
    for (int r = 0; r < h; ++r) {
        float v = (float)r / (h - 1);
        float edge = std::min(v, 1 - v);
        int32_t half = v > 0.5f ? 9 : 0;
        float inSeal = 1 - smoothstep(sealV - 0.003f, sealV + 0.002f, edge);
        float inBody = 1 - inSeal;
        float past = edge - sealV;
        float pleat = past > 0 ? std::exp(-past / 0.045f) : 0;
        for (int c = 0; c < w; ++c) {
            float u = (float)c / (w - 1);
            float t = inSeal * (55e-5f * std::sin(u * tau * 118) + 5e-4f * noise::fbm(u * 24, v * 30 + (float)half, 5, 2));
            t -= 0.0011f * std::exp(-std::pow((edge - sealV) / 0.0024f, 2.f));
            t += inBody * 42e-5f * noise::fbm(u * 13, v * 22, 9, 4);
            if (pleat > 0.01f) {
                float p = 1 - std::fabs(std::sin((u * 52 + 2.2f * noise::fbm(u * 3, v * 8 + (float)half, 13, 2)) * (float)M_PI));
                t += inBody * pleat * 7e-4f * (p * p - 0.35f);
            }
            float side = std::min(u, 1 - u);
            t += inBody * 6e-4f * std::exp(-std::pow((side - 0.045f) / 0.006f, 2.f));
            field[(size_t)r * w + c] = t;
        }
    }
    // Long creases.
    noise::Generator gen(4);
    for (int i = 0; i < 18; ++i) {
        float cx = (0.12f + gen.next() * 0.76f) * pouch::width;
        float cy = (sealV + 0.06f + gen.next() * (1 - 2 * sealV - 0.12f)) * pouch::height;
        float angle = gen.next() * (float)M_PI;
        float len = 0.12f + gen.next() * 0.42f;
        float depth = (gen.next() < 0.55f ? -1.f : 1.f) * (3e-4f + gen.next() * 6e-4f);
        float radius = 0.003f + gen.next() * 0.0035f;
        float x0 = cx - std::cos(angle) * len / 2, y0 = cy - std::sin(angle) * len / 2;
        float x1 = cx + std::cos(angle) * len / 2, y1 = cy + std::sin(angle) * len / 2;
        int c0 = std::max(0, (int)std::floor((std::min(x0, x1) - radius * 2) / dx));
        int c1 = std::min(w - 1, (int)std::ceil((std::max(x0, x1) + radius * 2) / dx));
        int r0 = std::max(0, (int)std::floor((std::min(y0, y1) - radius * 2) / dy));
        int r1 = std::min(h - 1, (int)std::ceil((std::max(y0, y1) + radius * 2) / dy));
        float len2 = len * len;
        if (c0 > c1 || r0 > r1) continue;
        for (int r = r0; r <= r1; ++r) for (int c = c0; c <= c1; ++c) {
            float px = c * dx, py = r * dy;
            float s = clamp01(((px - x0) * (x1 - x0) + (py - y0) * (y1 - y0)) / len2);
            float d = std::hypot(px - (x0 + s * (x1 - x0)), py - (y0 + s * (y1 - y0)));
            if (d < radius) field[(size_t)r * w + c] += depth * std::pow(std::max(0.f, std::sin((float)M_PI * s)), 0.6f) * std::pow(1 - d / radius, 1.6f);
        }
    }
    WrinkleNormalMap map;
    map.rgba.assign((size_t)w * h * 4, 255);
    for (int r = 0; r < h; ++r) {
        int up = std::max(r - 1, 0), down = std::min(r + 1, h - 1);
        for (int c = 0; c < w; ++c) {
            int left = std::max(c - 1, 0), right = std::min(c + 1, w - 1);
            float gx = (field[(size_t)r * w + right] - field[(size_t)r * w + left]) / ((right - left) * dx);
            float gy = (field[(size_t)down * w + c] - field[(size_t)up * w + c]) / ((down - up) * dy);
            vec3 n = normalize(vec3(-gx, -gy, 1));
            size_t i = ((size_t)r * w + c) * 4;
            map.rgba[i] = (uint8_t)clampf((n.x * 0.5f + 0.5f) * 255, 0, 255);
            map.rgba[i + 1] = (uint8_t)clampf((n.y * 0.5f + 0.5f) * 255, 0, 255);
            map.rgba[i + 2] = (uint8_t)clampf((n.z * 0.5f + 0.5f) * 255, 0, 255);
        }
    }
    return map;
}

} // namespace ck
