plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.amazingcards.cardkit"
    compileSdk = 35
    ndkVersion = "28.2.13676358"

    defaultConfig {
        minSdk = 29
        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++20", "-fno-exceptions", "-fno-rtti")
                arguments += listOf("-DANDROID_STL=c++_static")
            }
        }
        ndk { abiFilters += listOf("arm64-v8a") }
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.5"
        }
    }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin { jvmToolchain(17) }
    sourceSets["main"].kotlin.srcDirs("src/main/kotlin")
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.02.00")
    api(composeBom)
    api("androidx.compose.ui:ui")
    api("androidx.compose.foundation:foundation")
    api("androidx.compose.material3:material3")
    api("androidx.compose.ui:ui-graphics")
    api("androidx.compose.material:material-icons-core")
    api("androidx.core:core-ktx:1.16.0")
}

// The SPIR-V shaders are produced by the native build into src/main/assets:
// the asset tasks must wait for it, or the APK ships stale shaders.
afterEvaluate {
    listOf("Debug", "Release").forEach { variant ->
        val native = tasks.findByName("externalNativeBuild$variant") ?: return@forEach
        tasks.matching { it.name == "merge${variant}Assets" || it.name == "package${variant}Assets" || it.name == "generate${variant}Assets" }
            .configureEach { dependsOn(native) }
    }
}
