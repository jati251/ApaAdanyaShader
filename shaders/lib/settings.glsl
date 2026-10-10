#ifndef AA_SETTINGS
#define AA_SETTINGS

// ========== [ LIGHTING & SHADOWS ] ==========
#define SHADOWS // Real-Time Dynamic Shadows
#define SHADOW_SAMPLES 2 // [1 2 4 6 8]
//#define CONTACT_HARDENING_SHADOWS // Bounded solar PCSS; requires 6/8 shadow taps
const int shadowMapResolution = 1024; // [256 512 1024 2048 4096]
const float shadowDistance = 96.0; // [48.0 64.0 80.0 96.0 112.0 144.0 176.0 224.0]
const float sunPathRotation = -25.0; // [-45.0 -35.0 -25.0 -15.0 0.0 15.0 25.0 35.0 45.0]
#define SHADOW_ALPHA_TEST // Cutout Alpha Testing for Shadows
#define CLOUD_SHADOWS // Moving Cloud Shadows
#define CLOUD_SHADOW_STRENGTH 0.75 // [0.30 0.45 0.52 0.65 0.75 0.85]
//#define ATMOSPHERIC_LIGHTING // Time/weather dependent hemispherical sky fill
#define SSAO // Screen-Space Ambient Occlusion
#define SSAO_SAMPLES 8 // [4 6 8 12]
#define SSGI // Screen-Space Indirect Light
#define GI_SAMPLES 2 // [1 2 3 4 5 6 8]
#define GI_STRENGTH 0.65 // [0.15 0.30 0.45 0.50 0.55 0.65 0.85]
#define GI_RADIUS 8.0 // [4.0 8.0 12.0 16.0]
#define GI_TRACE_STEPS 24 // [16 24 32 48]
#define GI_DISTANCE 64.0 // [32.0 48.0 64.0 96.0]
#define VOLUMETRIC_LIGHT // Volumetric Light Shafts
#define VL_SAMPLES 8 // [4 6 8 12 16]
#define NIGHT_BRIGHTNESS 1.5 // [0.5 1.0 1.5 2.0 3.0]
#define CAVE_BRIGHTNESS 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define TORCH_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]

// ========== [ SKY & ATMOSPHERE ] ==========
#define CLOUDS 1 // [0 1 2]
#define CLOUD_DETAIL // 3D Fractal Cauliflower Billow Noise
#define CLOUD_STEPS 12 // [6 8 10 12 16 20 22 24 28 32]
#define CLOUD_COVERAGE 0.48 // [0.20 0.30 0.40 0.48 0.55 0.65 0.80]
#define CLOUD_ALTITUDE 360.0 // [260.0 300.0 360.0 420.0 480.0]
#define CLOUD_LAYERS 2 // [1 2 3]
#define CLOUD_LIGHT_SAMPLES 2 // [2 4 6]
#define STARS // Night Sky Stars
#define SUN_MOON_GLOW // Celestial Body Atmospheric Corona
#define FOG_ENABLED // Atmospheric Distance Fog
#define FOG_DENSITY 1.0 // [0.0 0.25 0.5 0.65 0.75 0.80 1.0 1.5 2.0]

// ========== [ WATER & REFLECTIONS ] ==========
#define WATER_REFRACTION // Underwater Optical Distortion
#define WATER_CAUSTICS // Sunlight Refraction Patterns on Seabed
#define SSR // Screen-Space Ray-Traced Reflections
//#define LIGHT_SPACE_FALLBACK // Sun-visible off-screen geometry; requires shadows
//#define DEPTH_HIERARCHY // Conservative min/max depth tiles; OpenGL 4.3
//#define SVGF_DENOISER // Temporal moments and three edge-aware a-trous passes
#define SSR_STEPS 24 // [8 12 16 18 24 28 32 40 48 56 64]
#define WATER_OCTAVES 7 // [2 3 4 5 6 7]
#define WATER_WAVES 0.65 // [0.0 0.25 0.45 0.65 0.85 1.0]
#define WATER_CLARITY 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define WATER_ROUGHNESS 0.10 // [0.06 0.10 0.14 0.20 0.28]

// ========== [ WORLD & MATERIALS ] ==========
#define WAVING_FOLIAGE // Wind in Plants & Leaves
#define WAVING_PLANTS // Waving Grass, Crops, & Flowers
#define WAVING_LEAVES // Waving Tree Leaves
#define WIND_SPEED 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define RAIN_PUDDLES // Dynamic Rain Puddles & Wet Surfaces
#define MATERIAL_FILTER 4 // [0 2 4 8] Atlas-safe smooth/aniso filtering for high-resolution packs
//#define RESOURCE_NORMALS // Tangent-Space Normal Maps
//#define RESOURCE_SPECULAR // LabPBR smoothness, reflectance and emission
//#define POM // LabPBR height-map parallax on terrain
#define POM_STEPS 16 // [8 16 24 32 48]
#define POM_DEPTH 0.25 // [0.0 0.05 0.10 0.15 0.25]
#define POM_DISTANCE 24.0 // [8.0 16.0 24.0 32.0 48.0 64.0]
#define SPECULAR_AA // Filter subpixel highlights
#define SOFT_PARTICLES // Fade translucent particles at opaque surfaces
#define PARTICLE_SOFTNESS 0.35 // [0.10 0.20 0.35 0.50 0.75]
#define PARTICLE_LIGHTING // Directional light for particles
#define WEATHER_OPACITY 0.65 // [0.25 0.40 0.65 0.80 1.0]

// ========== [ IMAGE & COLOR ] ==========
#define TONEMAP_OPERATOR 0 // [0 1 2 3 4 5]
#define COLOR_SATURATION 1.10 // [0.60 0.80 0.90 1.0 1.05 1.10 1.20 1.35 1.50]
#define COLOR_VIBRANCE 0.15 // [-0.50 -0.25 0.0 0.15 0.30 0.50 0.75]
#define COLOR_CONTRAST 1.04 // [0.85 0.90 1.0 1.04 1.10 1.18 1.30]
#define EXPOSURE 1.0 // [0.6 0.8 1.0 1.2 1.4]
//#define AUTO_EXPOSURE // Scene-linear luminance metering with temporal adaptation
#define COLOR_TEMPERATURE 0.0 // [-1.0 -0.75 -0.50 -0.25 0.0 0.25 0.50 0.75 1.0]
#define COLOR_TINT 0.0 // [-1.0 -0.50 0.0 0.50 1.0]
#define BLOOM // Bloom Glow Effect
#define BLOOM_STRENGTH 0.08 // [0.02 0.05 0.06 0.08 0.12 0.18]
#define TAA // Temporal Anti-Aliasing & Stability
#define TAA_BLEND 0.80 // [0.40 0.60 0.70 0.75 0.80 0.85 0.88 0.94]
//#define FXAA // Optional spatial edge smoothing; temporal presets use TAA
#define COLOR_DITHERING // Temporal Gradient Dithering
#define MOTION_BLUR // Lightweight fixed two-tap camera motion blur

// FSR 1 spatial upscaling; zero preserves native rendering.
#define UPSCALE_QUALITY 2 // [0 1 2 3]
#define UPSCALE_SHARPNESS 0.20 // [0.0 0.20 0.40 0.50 0.60 0.80 1.0]

// Effects also have independent reconstruction.
#define CLOUD_RECONSTRUCTION // Cached volumetric cloud layer
//#define CLOUD_FULL_RES // Full-resolution cloud cache; Extreme quality
#define TEMPORAL_CLOUDS // Reproject and clamp cloud history
#define HARDWARE_PCF // Four bilinear hardware-PCF taps with the original PCSS blocker search
#define HALF_RES_LIGHTING // Bilateral SSAO/GI and volumetric-light reconstruction
//#define TEMPORAL_INDIRECT // Signal-specific AO/GI history; requires HALF_RES_LIGHTING

const float ambientOcclusionLevel = 0.65;
const float wetnessHalflife = 90.0;
const float drynessHalflife = 180.0;
const float centerDepthHalflife = 0.5;

#endif
