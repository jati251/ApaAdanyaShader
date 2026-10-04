#ifndef AA_SETTINGS
#define AA_SETTINGS
#define SHADOWS // Real-Time Dynamic Shadows
#define SSAO // Screen-Space Ambient Occlusion
#define SSR // Screen-Space Ray-Traced Reflections
#define SSGI // Screen-Space Indirect Light
#define CLOUD_SHADOWS // Moving Cloud Shadows
#define VOLUMETRIC_CLOUDS // Volumetric Clouds
#define FAST_CLOUDS // Lightweight 2D Clouds (Fallback)
#define VOLUMETRIC_LIGHT // Volumetric Light Shafts
#define WAVING_FOLIAGE // Wind in Plants & Leaves
#define BLOOM // Bloom Glow Effect
#define FXAA // Edge Anti-Aliasing
#define SHADOW_ALPHA_TEST // Cutout Alpha Testing for Shadows
//#define RESOURCE_NORMALS // Resource Pack Normal Maps
#define SSR_STEPS 24 // [12 18 24 32 48 64]
#define GI_SAMPLES 3 // [2 3 4 6 8]
#define CLOUD_STEPS 12 // [8 12 16 20 24 32]
#define SHADOW_SAMPLES 6 // [2 4 6 8 12 16]
#define WATER_WAVES 0.65 // [0.25 0.45 0.65 0.85 1.0]
#define WATER_ROUGHNESS 0.14 // [0.06 0.10 0.14 0.20 0.28]
#define COLOR_SATURATION 1.05 // [0.85 0.95 1.0 1.05 1.10 1.20]
#define COLOR_CONTRAST 1.08 // [0.90 1.0 1.04 1.08 1.12 1.20]
#define WATER_CLARITY 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define CLOUD_COVERAGE 0.48 // [0.30 0.40 0.48 0.55 0.65]
#define EXPOSURE 1.0 // [0.7 0.85 1.0 1.15 1.3]
#define BLOOM_STRENGTH 0.08 // [0.0 0.04 0.08 0.12 0.18]
#define GI_STRENGTH 0.45 // [0.0 0.25 0.45 0.65 0.85]
#define NIGHT_BRIGHTNESS 1.5 // [0.5 1.0 1.5 2.0 3.0]
#define FOG_DENSITY 1.0 // [0.5 0.75 1.0 1.5 2.0]
const int shadowMapResolution = 1024; // [512 1024 2048 4096]
const float shadowDistance = 144.0; // [80.0 112.0 144.0 176.0 224.0]
const float sunPathRotation = -25.0;
const float ambientOcclusionLevel = 0.65;
const float wetnessHalflife = 90.0;
const float drynessHalflife = 180.0;
#endif



