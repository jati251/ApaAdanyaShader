# ApaAdanyaShader

Minecraft Java shaderpack for Iris + Sodium on Windows and macOS. Development target: Minecraft 26.3 / Iris 1.11.7. All shader stages use GLSL 330; no compute shaders, Metal bridge, RTX hardware or additional upscaling mod are required. Automated GPU validation runs on Apple M1; Windows driver and in-game validation are still pending.

## Current update

See [Realism setup and feature status](REALISM.md) for the water/cloud/weather update, original effects resource pack, native and FSR profiles, performance tradeoffs, Windows transfer instructions and actual DLSS / frame-generation limitations. The primary target is RTX 3080 Ti; macOS is a supported development and validation platform.

The game most recently saved **Realism + FSR Ultra Quality** settings; **Realism (Optimized)** is the native-resolution alternative. **Realism + FSR Ultra Quality** uses the same effects with EASU/RCAS scaling; **Realism + High Screen-Space Tracing** increases SSR/GI samples. Saved profiles are in `presets/`.

## Enable the upscaler

Choose a quality profile first, then open **Shader Pack Settings → Performance & Reconstruction → AMD FSR 1 Upscaling**.

| Mode | Internal width / height | Approximate scene pixel count | Intended use |
| --- | --- | --- | --- |
| Native | 100% | 100% | Default; preserve original scene resolution |
| Ultra Quality | 77% | 59% | First setting to compare against Native |
| Quality | 67% | 44% | More GPU savings, more fine-detail loss |
| Balanced | 59% | 35% | Larger performance/quality tradeoff |

These percentages describe rendered pixels, **not measured FPS gains**. Shadow maps, geometry submission, CPU simulation, buffer clears and parts of the renderer retain their original costs. EASU and RCAS add full-screen work. Existing buffers retain their allocations; this is a shading optimization, not a VRAM reduction. Upscaling can be slower when the GPU's scene shading is already cheap or the game is CPU-limited.

**FSR RCAS Sharpness** controls final sharpening; zero disables RCAS. Native sharpening is bypassed while FSR is active to avoid sharpening twice. Choosing another quality profile resets upscaling to Native. The game most recently saved Realism + FSR Ultra Quality settings; prior settings have been backed up.

This is a real spatial upscaler: geometry and scene/effect passes render a smaller viewport, EASU reconstructs the display-sized image, then RCAS sharpens it. The shaderpack does not downsample a fully rendered scene and call it a performance improvement. The Minecraft HUD remains outside the shader's world upscale.

FSR 1 does not generate frames and cannot recover all missing fine detail. It does not require motion vectors or camera jitter. Temporal stabilization plus FXAA provides input filtering; the native temporal filter is not jittered TAA or temporal super resolution. For scaled DOF, autofocus reads the actual viewport center directly; Iris's native smoothed-center-depth value belongs to the full allocation and is only used in Native mode.

The same implementation works at the shader-language level on Windows and macOS. Begin Windows testing with Ultra Quality, compare Native at the same position/resolution, and keep whichever has better frame times and acceptable detail. Full Iris runtime behavior still needs checking on both platforms, including window resizing, DH boundaries, block outlines and hand/translucent geometry.

## Visual features

- Sun/moon lighting, filtered shadow maps, foliage transmission, SSAO, screen-space indirect light and volumetric light shafts.
- Procedural day/night sky, stars, 2D/volumetric clouds, cloud shadows and distance fog. Cloud reconstruction has its own temporal history and camera/weather rejection.
- Water Fresnel, SSR, refraction, wave normals, wavelength-dependent absorption, shoreline foam and procedural caustics.
- Wind, wet materials and puddles. Optional terrain LabPBR normal, AO, roughness, F0, emission, subsurface and porosity inputs. Metals use albedo as F0; exact conductor Fresnel and predefined metal constants are not implemented.
- Terrain POM from the normal texture's alpha height channel, with shared displaced albedo/specular coordinates, atlas bounds, explicit gradients and distance fading. POM does not modify mesh silhouettes, geometry depth or cast shadows.
- Separate opaque/translucent particles, soft intersections, adjustable weather opacity, HDR bloom, six tone-map choices, color profiles, vignette, optional camera motion blur and depth of field.
- Shared Overworld, Nether, End and Distant Horizons programs. Half-resolution cloud, AO/GI and large-bokeh reconstruction remain individually selectable.

Photoreal material relief needs a compatible normal/height/specular resource pack. The installed Faithful 64x archive has no terrain `_n` / `_s` maps; its two similarly named files are alphabet particles. Enabling POM alone cannot invent material relief. Geometry remains Minecraft's block geometry, and screen-space GI/reflections cannot see surfaces absent from the depth/color buffers.

## Profiles

| Profile | Main effects | DOF / motion blur | Shadow map |
| --- | --- | --- | --- |
| Potato | No clouds, shadows, AO, GI, SSR or bloom | Off | Disabled |
| Low | 2D clouds, foliage wind, FXAA, 2-tap shadows | Off | 512 |
| Medium | Half-resolution volumetric clouds, SSAO, SSR, bloom | Off | 1024 |
| High | Adds GI, light shafts, LabPBR/POM | Off | 2048 |
| Ultra | 22 cloud steps, 40 SSR steps, 5 GI rays, 24 POM steps | Off | 2048 |
| Extreme | 28 cloud steps, 56 SSR steps, 6 GI rays, 32 POM steps; native AO/GI | DOF 20 samples; motion blur 12 | 4096 |

All profiles inherit a complete base, resetting expensive settings when switching down. Custom camera, color and upscaling settings should be applied after choosing a profile. Native mode plus disabling cloud/lighting/DOF reconstruction provides a full-resolution reference.

## Pipeline and buffers

| Stage | Output / operation |
| --- | --- |
| prepare / prepare1 | Native-size sky cache / cloud-shadow cache |
| gbuffers / DH | Scene color, normals, material data, optional reflectance |
| deferred / deferred1 | Reduced cloud layer / cloud history |
| deferred2 | Reduced AO/GI |
| deferred3 | Scene lighting, sky, reflections; opaque copy for water |
| composite | Fog and light shafts after translucency |
| composite1 / 2 / 3 | Quarter-size bloom extraction / horizontal / vertical blur |
| composite4 | Optional half-size DOF |
| composite5 | HDR temporal history; lens, bloom and display grading |
| composite6 | Upscaling only: FXAA and camera/post effects at render resolution |
| composite7 | Upscaling only: EASU to display-sized `colortex14` |
| final | Native: camera/post effects; upscaled: RCAS to display |

`colortex13.rgb` is pre-lens HDR history; alpha stores positive view-space depth, -1 for sky or -2 for a hand. `colortex12` is reused for AO/GI and DOF. Upscaling uses lower-left active viewports with clamped logical-UV sampling. Shadow and environment-cache viewports remain unchanged. `colortex14` shrinks to 1×1 and both upscale-only composite passes are disabled in Native mode.

## Validation and use

```sh
python3 tools/validate.py
python3 tools/validate.py --static
python3 tools/validate.py --images-only
```

The validator checks profile completeness, option ranges, translations, dimension entry points, GPU compile/link variants and synthetic image regressions. It uses macOS CGL or a hidden GLFW context on Windows/Linux (`python -m pip install glfw`). Both paths compile GLSL 330. Compatibility builtins are bridged to core inputs and DH helpers are stubbed; this is not the complete Iris patching/binding pipeline. See [VALIDATION.md](VALIDATION.md).

Select the pack and reload it in Minecraft after edits. This instance binds Iris reload to **R**. Check the same loaded scene before/after, with a fixed display resolution and render distance. Record median and 95th-percentile frame times after chunk generation settles. Review day/night/rain, water/underwater, moving foliage/entities, particles, all dimensions, DH transitions, resizing, focus and outlines. Automated fixtures do not establish in-game FPS gains or approve the final look.

## Other upscalers and frame generation

FSR 2/3 temporal upscaling, DLSS and XeSS need a separate renderer/mod integration with jitter and reliable motion/depth inputs. The [Super Resolution project](https://github.com/IReallyWantToSleep/superresolution) provides such integration on supported Windows/Linux x64 configurations; it is not a dependency of this pack and was not installed. Its custom shader interface also requires the pack to control render scaling itself. Do not enable two independent resolution scalers together.

Frame generation additionally needs interpolation scheduling, frame pacing and UI/presentation integration outside this shaderpack. No frame-generation feature is claimed or included. See AMD's [frame interpolation integration](https://gpuopen.com/manuals/fidelityfx_sdk/techniques/frame-interpolation-swap-chain/).

References: [AMD FSR 1 source](https://github.com/GPUOpen-Effects/FidelityFX-FSR), [Iris gbuffers and fallbacks](https://shaders.properties/current/reference/programs/gbuffers/), [LabPBR specification](https://shaderlabs.org/wiki/LabPBR_Material_Standard), [Filament PBR reference](https://github.com/google/filament/blob/main/docs/Filament.md.html). Third-party attribution is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
