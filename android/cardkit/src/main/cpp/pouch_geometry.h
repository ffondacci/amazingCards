// The pouch mesh and its wrinkle normal map, ports of PouchGeometry.swift
// and WrinkleNormalMap.swift. Built once per look, on a worker thread.
#pragma once
#include <vector>
#include <cstdint>
#include "stage_math.h"

namespace ck {

/// Vertex layout shared with the shaders: 48 bytes, like simd's SIMD3 strides.
struct PouchVertex {
    vec3 position; float pad0 = 0;
    vec3 normal; float pad1 = 0;
    vec2 uv; float pad2[2] = {0, 0};
};
static_assert(sizeof(PouchVertex) == 48, "vertex layout must match the shaders");

struct PouchMesh {
    std::vector<PouchVertex> vertices;
    std::vector<uint32_t> indices;

    static PouchMesh make(bool back, int32_t seed, float puff, float wrinkles);
    /// Rounded rectangle of a card, 0.8 wide, as a fan of triangles.
    static PouchMesh card(float aspect = 0.716f);
    /// A rounded slab (the pull tab and its slider): two faces and the wall between them.
    static PouchMesh slab(float w, float h, float d, float r);
    void computeNormals();
};

struct WrinkleNormalMap {
    static constexpr int width = 512;
    static constexpr int height = 952;
    std::vector<uint8_t> rgba;
    static WrinkleNormalMap make();
};

} // namespace ck
