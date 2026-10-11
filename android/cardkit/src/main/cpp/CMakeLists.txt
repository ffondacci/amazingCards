cmake_minimum_required(VERSION 3.22)
project(cardstage LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# GLSL → SPIR-V with the NDK's glslc, into the library's assets.
set(GLSLC "${ANDROID_NDK}/shader-tools/${ANDROID_HOST_TAG}/glslc")
if(NOT EXISTS "${GLSLC}")
    file(GLOB GLSLC_CANDIDATES "${ANDROID_NDK}/shader-tools/*/glslc")
    list(GET GLSLC_CANDIDATES 0 GLSLC)
endif()
set(SHADER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/shaders")
set(SHADER_OUT "${CMAKE_CURRENT_SOURCE_DIR}/../assets/shaders")
file(MAKE_DIRECTORY "${SHADER_OUT}")
set(SHADERS pouch.vert pouch.frag sprite.vert shadow.frag aura.frag background.vert background.frag flake.vert flake.frag particle.vert particle.frag)
set(SPV_FILES)
foreach(S ${SHADERS})
    set(OUT "${SHADER_OUT}/${S}.spv")
    add_custom_command(
        OUTPUT "${OUT}"
        COMMAND "${GLSLC}" -O --target-env=vulkan1.1 -I "${SHADER_DIR}" "${SHADER_DIR}/${S}" -o "${OUT}"
        DEPENDS "${SHADER_DIR}/${S}" "${SHADER_DIR}/common.glsl"
        COMMENT "glslc ${S}")
    list(APPEND SPV_FILES "${OUT}")
endforeach()
add_custom_target(stage_shaders ALL DEPENDS ${SPV_FILES})

add_library(cardstage SHARED
    pouch_geometry.cpp
    stage_particles.cpp
    stage_scene.cpp
    stage_opening.cpp
    stage_pieces.cpp
    stage_cards.cpp
    vk_context.cpp
    stage_renderer.cpp
    stage_jni.cpp)
add_dependencies(cardstage stage_shaders)
target_compile_definitions(cardstage PRIVATE VK_USE_PLATFORM_ANDROID_KHR)
target_compile_options(cardstage PRIVATE -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers)
target_link_libraries(cardstage vulkan android log)
