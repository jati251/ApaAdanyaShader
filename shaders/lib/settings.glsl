#ifndef AA_SETTINGS
#define AA_SETTINGS

// ========== [ LIGHTING & SHADOWS ] ==========
#define SHADOWS // Real-Time Dynamic Shadows
#define SHADOW_SAMPLES 2 // [1 2 4 6 8]
const int shadowMapResolution = 1024; // [256 512 1024 2048 4096]
const float shadowDistance = 96.0; // [48.0 64.0 80.0 96.0 112.0 144.0 176.0 224.0]
const float sunPathRotation = -25.0; // [-45.0 -35.0 -25.0 -15.0 0.0 15.0 25.0 35.0 45.0]
#define SHADOW_ALPHA_TEST // Cutout Alpha Testing for Shadows
#define CLOUD_SHADOWS // Moving Cloud Shadows
#define SSAO // Screen-Space Ambient Occlusion
#define SSAO_SAMPLES 8 // [4 6 8 12]
#define SSGI // Screen-Space Indirect Light
#define GI_SAMPLES 3 // [2 3 4 5 6 8]
#define GI_STRENGTH 0.45 // [0.15 0.30 0.45 0.50 0.55 0.65 0.85]
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
#define STARS // Night Sky Stars
#define SUN_MOON_GLOW // Celestial Body Atmospheric Corona
#define FOG_ENABLED // Atmospheric Distance Fog
#define FOG_DENSITY 1.0 // [0.0 0.25 0.5 0.65 0.75 0.80 1.0 1.5 2.0]

// ========== [ WATER & REFLECTIONS ] ==========
#define WATER_REFRACTION // Underwater Optical Distortion
#define WATER_CAUSTICS // Sunlight Refraction Patterns on Seabed
#define WATER_FOAM // Shoreline Wave Foam
#define SSR // Screen-Space Ray-Traced Reflections
#define SSR_STEPS 24 // [8 12 16 18 24 28 32 40 48 56 64]
#define WATER_OCTAVES 5 // [2 3 4 5 6 7]
#define WATER_WAVES 0.65 // [0.0 0.25 0.45 0.65 0.85 1.0]
#define WATER_CLARITY 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define WATER_ROUGHNESS 0.14 // [0.06 0.10 0.14 0.20 0.28]

// ========== [ WORLD & MATERIALS ] ==========
#define WAVING_FOLIAGE // Wind in Plants & Leaves
#define WAVING_PLANTS // Waving Grass, Crops, & Flowers
#define WAVING_LEAVES // Waving Tree Leaves
#define WIND_SPEED 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define RAIN_PUDDLES // Dynamic Rain Puddles & Wet Surfaces
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

// ========== [ POST-PROCESSING & COLOR GRADING ] ==========
#define COLOR_PROFILE 0 // [0 1 2 3 4 5 6 7]
#define TONEMAP_OPERATOR 0 // [0 1 2 3 4 5]
#define COLOR_SATURATION 1.10 // [0.60 0.80 0.90 1.0 1.05 1.10 1.20 1.35 1.50]
#define COLOR_VIBRANCE 0.15 // [-0.50 -0.25 0.0 0.15 0.30 0.50 0.75]
#define COLOR_CONTRAST 1.04 // [0.85 0.90 1.0 1.04 1.10 1.18 1.30]
#define EXPOSURE 1.0 // [0.6 0.8 1.0 1.2 1.4]
#define COLOR_TEMPERATURE 0.0 // [-1.0 -0.75 -0.50 -0.25 0.0 0.25 0.50 0.75 1.0]
#define COLOR_TINT 0.0 // [-1.0 -0.50 0.0 0.50 1.0]
#define BLOOM // Bloom Glow Effect
#define BLOOM_STRENGTH 0.08 // [0.02 0.05 0.06 0.08 0.12 0.18]
#define TAA // Temporal Anti-Aliasing & Stability
#define TAA_BLEND 0.80 // [0.40 0.60 0.70 0.75 0.80 0.85 0.88 0.94]
#define TAA_SHARPENING // Contrast-Adaptive Sharpening
#define TAA_SHARPEN_STRENGTH 0.40 // [0.20 0.35 0.40 0.45 0.60 0.80 1.00 1.25]
#define FXAA // Fast Approximate Anti-Aliasing
#define VIGNETTE // Lens Vignette
#define VIGNETTE_STRENGTH 0.30 // [0.15 0.20 0.25 0.30 0.45 0.60]
//#define CHROMATIC_ABERRATION // Lens optical dispersion
#define CA_STRENGTH 1.0 // [0.5 1.0 1.5 2.0 3.0]
//#define FILM_GRAIN // 35mm film grain texture
#define FILM_GRAIN_STRENGTH 0.03 // [0.01 0.02 0.03 0.05 0.08]
#define COLOR_DITHERING // Temporal Gradient Dithering
//#define DOF // Lens depth of field
#define DOF_AUTOFOCUS // Smooth focus at the crosshair
#define DOF_FOCUS_DISTANCE 8.0 // [1.0 2.0 3.0 5.0 8.0 12.0 24.0 48.0 128.0]
#define DOF_FOCAL_LENGTH 50.0 // [24.0 35.0 50.0 70.0 85.0]
#define DOF_FSTOP 2.8 // [1.4 2.0 2.8 4.0 5.6 8.0]
#define DOF_SAMPLES 16 // [8 16 20 24 32]
#define DOF_MAX_RADIUS 12.0 // [6.0 8.0 10.0 12.0 16.0 24.0]
//#define MOTION_BLUR // Camera & world motion blur
#define MOTION_BLUR_STRENGTH 0.50 // [0.10 0.20 0.35 0.40 0.50 0.75 1.00 1.50 2.00]
#define MOTION_BLUR_SAMPLES 8 // [4 6 8 12 16 24]
//#define MOTION_BLUR_LOW_LATENCY // High-performance 5-sample mode with tighter blur for competitive play
//#define MOTION_BLUR_HAND // Blur first-person hand and held item

// FSR 1 spatial upscaling; zero preserves native rendering.
#define UPSCALE_QUALITY 0 // [0 1 2 3]
#define UPSCALE_SHARPNESS 0.40 // [0.0 0.20 0.40 0.60 0.80 1.0]

// Effects also have independent reconstruction.
#define CLOUD_RECONSTRUCTION // Half-resolution volumetric cloud layer
#define TEMPORAL_CLOUDS // Reproject and clamp cloud history
#define HALF_RES_LIGHTING // Bilateral SSAO/GI reconstruction
#define HALF_RES_DOF // Bilateral lens reconstruction

const float ambientOcclusionLevel = 0.65;
const float wetnessHalflife = 90.0;
const float drynessHalflife = 180.0;
const float centerDepthHalflife = 0.5;

#endif
