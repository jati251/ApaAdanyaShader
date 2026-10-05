# Renderer realism — 5 October 2026

Implemented in the existing ApaAdanyaShader, using the supplied master plan as a technology reference. Existing local changes were preserved. The pre-edit shaderpack and active settings are backed up under the instance's `.codex-backups/photoreal-refactor-20261005/` directory.

## Changes

- Shared LabPBR decoding in `shaders/lib/material.glsl`. Green remains linear dielectric F0; IDs 230–237 use the standard conductor optical constants with albedo tint; other metal IDs retain the albedo-F0 fallback. Perceptual roughness is squared once in GGX. Alpha 255 remains non-emissive. Missing specular maps retain the vanilla defaults.
- Burley diffuse added alongside existing height-correlated Smith/GGX and specular normal-variance filtering.
- New material-response G-buffer, `colortex15`: linear diffuse reflectance times material AO in RGB; approximate ambient luminance fraction in alpha. Screen GI now multiplies this response rather than `sqrt(shadedColor)`. Metals have no diffuse GI. Screen AO attenuates the ambient fraction instead of the whole direct/emissive result. The scalar fraction is a compact approximation for differently colored light sources.
- Environment reflections add a separate specular lobe instead of mixing away the entire illuminated surface. Rough surfaces use a small five-direction sky-cache convolution. Screen rays are skipped above perceptual roughness 0.60; sky fallback is occluded by skylight. This is an approximate rough reflection filter, not GGX VNDF sampling or off-screen world tracing.
- Screen GI uses receiver cosine/PDF cancellation consistently, rejects hit back faces, weights hit confidence and limits fireflies by luminance rather than clipping individual color channels. Rays now take 16 coarse steps instead of 10; reconstruction accepts valid partial bilateral coverage instead of repeating full ray work at most edges.
- Optional solar contact hardening: eight blocker taps, orthographic depth conversion that accounts for the pack's shadow z distortion, solar angular radius, and distortion-aware penumbra projection. Filtering remains capped to five texels. Active at six/eight shadow samples; cheaper variants retain PCF. This remains one distorted shadow map, not cascaded shadows.
- Optional, separate GI/AO temporal history in `colortex17/18`, validated per bilinear tap using previous-view depth and world normal. Camera cuts, FOV changes, invalid frames and entities reject reuse. Directions cycle over 32 frames. Half-resolution lighting is required; full-resolution variants retain the unaccumulated path. History is independent of DOF and display TAA.
- Optional exposure pass, `deferred4`, meters opaque scene-linear HDR using 64 center-weighted log-luminance samples into a persistent 1×1 `colortex16`. Exposure stays within 0.35–3.0, adapts faster toward bright scenes and more slowly toward dark scenes, and resets invalid history/camera teleports. `EXPOSURE` remains a user multiplier. Water/translucency are drawn after metering; this is not a histogram or local tone mapper.

## Current settings and costs

The active custom settings enable contact hardening, adaptive exposure, temporal indirect light and reduced-resolution lighting/clouds. All ten menu profiles now have matching complete disk presets and Indonesian/English descriptions. Medium enables adaptive exposure and temporal AO; High/Ultra enable contact hardening and temporal GI. Extreme disables indirect history because its lighting runs at full resolution. DOF, motion blur and TAA sharpening are disabled in the current gameplay configuration. Cinematic options remain available in their profile. FXAA is retained: the existing temporal filter has no projection jitter, so it does not replace coverage anti-aliasing.

No unreachable GLSL or program modules were found in the include graph. Dimension entry points and FSR support are used, so they were retained. Savings are from optional pass bypasses, bounded ray/filter work and reduced fallback work, not deletion of active renderer modules. PCSS, rough environment filtering, the new material attachment and temporal histories add costs. No net FPS gain is claimed without an in-game frame-time capture.

At native 1920×1080, the new response and half-resolution GI history logical targets total about 15.8 MiB; allocating both ping-pong sides can double that. The exposure target is negligible. Allocation details depend on Iris. These additions require Iris 1.10.5+ for attachments above 15; the installed instance uses Iris 1.11.7.

## Validation and remaining limits

Run `python -B tools/validate.py`. It compiles all quality variants, the active instance configuration, all dimensions, and DH on/off, then executes synthetic GPU fixtures. Run `--images-only` for image/math regressions or `--static` for menu/profile/translation checks.

Static checks require every exported preset to exactly match its resolved menu profile, with unique option keys and both profile descriptions. Iris clear-color directives require four explicit literal components; a scalar vec4 constructor previously triggered the runtime parser error and is corrected. New GPU regressions cover conductor spectra, linear dielectric F0, missing-map and emission sentinels, zero metal diffuse, ambient-only AO, solar penumbra growth, exposure bounds/adaptation/reset and indirect depth/normal/history rejection. The retained latest validation record is `artifacts/validation.log`. Intermediate logs and synthetic preview files are removed after verification.

This remains a hybrid renderer with forward material lighting and deferred screen-space effects. It does not implement the entire master plan. There is no world voxel cache, ReSTIR, DDGI, off-screen geometry GI/reflections, path tracing, Hi-Z pyramid, motion-vector G-buffer, jittered TAA, progressive photo accumulation, native hardware RT or neural reconstruction. Existing water, atmosphere, POM, lens, FSR and DH implementations remain in place. Extending those architectures requires a separately validated implementation, not preset switches.

The instance currently selects only the vanilla resource pack. It therefore has no supplied LabPBR normal/height/specular asset set. Lighting can improve substantially, but photographic surface detail requires appropriate PBR textures and scene assets. No new resource pack was downloaded or installed.

Native NVIDIA driver compilation and synthetic fixtures do not establish final Iris framebuffer bindings, visual signoff, weather/dimension transitions or gameplay frame time. Reload the shader in Minecraft to apply source/settings changes; these need in-game verification. No runtime verification was claimed from an earlier log entry.

## References

- Supplied `minecraft_java_26_3_photorealistic_rendering_master_plan.md`.
- [LabPBR material standard](https://shaderlabs.org/wiki/LabPBR_Material_Standard): channel interpretation and conductor optical constants.
- [Filament](https://google.github.io/filament/main/filament.html): microfacet and rough diffuse material models.
- [NVIDIA PCSS integration](https://developer.download.nvidia.com/assets/gamedev/docs/PCSS_Integration.pdf): blocker search, penumbra estimation and filtering.
- [Iris color buffers](https://shaders.properties/current/reference/buffers/colortex/): extended attachment count, persistence and ping-pong behavior.

## Water, sky, particles and terrain

The existing water path retains crossing swells, analytic wave gradients, rain ripples, pixel-footprint filtering, Beer-Lambert absorption, Fresnel, Snell refraction and underwater total internal reflection. Reflection/refraction hits validate surface depth, with separate DH projection where needed. Shore foam, deep whitecaps and procedural caustics are bounded approximations. Waves shade the existing mesh; they do not change Minecraft fluid simulation or add tessellated ocean geometry.

Volumetric clouds retain shared volume bounds, weather density, edge erosion, directional extinction and approximate multiple scattering. A small periodic sky cache supplies environment reflections; cloud and indirect histories are separate. Sun/moon, stars, fog, foliage wind and volumetric light shafts remain available.

Cutout/translucent particles retain their masks, optional soft intersections and weather opacity. Fire and soul-fire use classified emissive materials; lightning flash lighting uses the actual lightning uniform. Opaque particles explicitly clear the material-response attachment so they cannot inherit the terrain receiver behind them.

The optional effects-pack generator in `tools/build_effects_pack.py` creates procedural fire, smoke, rain and splash assets; it is a reusable build tool, not a temporary experiment. No effects pack or PBR pack is automatically enabled. Terrain, entities, hands, Overworld/Nether/End wrappers and Distant Horizons support remain in the shaderpack.
