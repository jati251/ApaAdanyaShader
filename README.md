# ApaAdanyaShader

Minecraft shaderpack for Iris + Sodium, with six quality profiles and an OpenGL shader pipeline. The development instance uses Minecraft 26.3, Iris 1.11.7 and Apple M1. The pack uses the same Iris/OpenGL path on Windows and macOS; it does not require a Mac-only shader feature or a PC migration.

## Features

- Sun/moon lighting, filtered shadow maps, foliage transmission, SSAO, screen-space indirect light and volumetric light shafts.
- Procedural day/night sky, stars, 2D or volumetric clouds, cloud shadows and atmospheric fog. Cloud rays stop at the cloud layer exit and also support views from above the layer.
- Water Fresnel, screen-space reflections, refraction, animated wave normals, absorption, shoreline foam and procedural caustics.
- Wind, wet surfaces and puddles; optional LabPBR normal, material AO, smoothness, F0, emission and subsurface maps on terrain. Metallic materials use the standard's albedo-F0 fallback. Porosity and exact conductor Fresnel are not implemented.
- Terrain POM reads the alpha height channel of LabPBR normal maps. Albedo, normal, specular and emission maps share the displaced UV. Sampling wraps within the current quad's atlas region, uses explicit gradients, adapts to view angle and fades with distance/pixel footprint. Flat maps, head-on views, invalid tangent frames and foliage bypass the march.
- Separate opaque/translucent particle programs, particle sunlight and shadows, soft intersections with opaque terrain, and adjustable rain/snow opacity. The shader shades Minecraft's existing particles; it does not create new particle geometry or replace their textures.
- HDR bloom, filmic tone mapping, FXAA, ordered dithering and optional vignette.
- Adaptive reconstruction modes: half-resolution cloud and indirect-light passes, depth/normal-aware upsampling, temporal cloud history with camera/weather/frame rejection, and a half-resolution large-bokeh DOF path. The full-resolution reference path remains available by disabling the four controls in Performance & Reconstruction.
- Thin-lens DOF with smoothed crosshair autofocus or manual focus, aperture, focal length, bounded bokeh radius and 8–32 samples. The hand stays sharp, focused pixels skip the gathering loop, and distant terrain depth is supported. Blur is gathered before tone mapping. This is a single-layer screen-space approximation; occluded backgrounds and particle depths are unavailable.
- Complete Overworld, Nether and End program sets; DH terrain/water paths share their implementation between dimensions.

## Profiles

| Profile | Main workload | DOF | Shadow map |
| --- | --- | --- | --- |
| Potato | 2D clouds, 2 wave octaves; no shadow pass, bloom, SSAO, SSR or GI | Off | Disabled |
| Low | 2D clouds, foliage wind, FXAA, 1-tap shadows | Off | 512 |
| Medium | 3D clouds, SSAO, water SSR, bloom, soft particles | Off, available manually | 1024 |
| High | Adds GI, light shafts and resource-pack materials | 16 samples | 2048 |
| Ultra | Higher cloud/GI/reflection counts and 7 wave octaves | 24 samples | 2048 |
| Extreme | 32 cloud steps, 64 reflection steps, 8 GI rays | 32 samples | 4096 |

Profiles inherit a complete base, including all quality controls, so lowering the preset resets expensive settings. Selecting a profile also resets its camera and grading values; make custom adjustments after choosing the profile.

Bloom extraction runs at quarter width/height with 13 taps. Its Gaussian blur uses 7 bilinear taps per axis. Bloom passes are disabled when bloom is off, and the cloud-shadow pass is disabled when unused. Water foam does no work when disabled. Normal maps and detailed water use derivative-based specular filtering to reduce subpixel shimmer. Potato and Low leave the reconstruction passes off; Medium enables cloud reconstruction and history; High and above also enable AO/GI and large-bokeh reconstruction. POM is off for Potato/Low/Medium; High uses up to 16 steps within 24 blocks, Ultra 32 within 32 blocks, and Extreme 48 within 48 blocks. Three refinement samples follow the first height crossing. Distance fading begins at 65% of the selected range.

There is no universal FPS guarantee. Extreme increases both GPU work and memory use; resolution, render distance, DH generation, resource packs and scene complexity all affect frame time. On the M1 instance, start with Low or Medium and measure while the world has finished loading. Detailed photoreal surfaces require appropriate resource-pack textures; lighting alone retains Minecraft's block geometry and source texture detail.

## Use

1. Select `ApaAdanyaShader` in Iris Shader Packs.
2. Open Shader Pack Settings and select the desired profile. Existing saved overrides are preserved until you choose a profile.
3. Open **Lens & Depth of Field** for DOF. A lower f-number or longer focal length produces more blur. Disable autofocus for a fixed focus distance.
4. Open **Particles & Weather** for soft intersections and weather opacity. Open **World & Vegetation** for LabPBR controls.
5. For relief textures, enable **Resource Pack Normal Maps** and **Parallax Occlusion Mapping (POM)** under **World & Vegetation**, or select High/Ultra/Extreme. The resource pack must contain height information in the normal-map alpha channel. The default depth is 0.25 of a texture tile; lower it if a pack looks too deep. POM changes texture intersections, not mesh silhouettes, depth-buffer geometry or cast shadows. Height-field self-shadowing, entities, held items and DH LOD displacement are not implemented. Cropped/nonrectangular model UVs can produce approximate results.
6. Reload the pack after changing files. This instance maps Iris reload to **R** while in the world.

## Validation

Run from the shaderpack folder:

```sh
python3 tools/validate.py
```

The validator checks profile completeness, legal values, translated controls, option discovery and dimension entry points. It compiles and links every program for six presets, defaults, manual focus, three POM option combinations, a full-resolution reference, no-cloud-history mode and AO-only reconstruction, with DH enabled and disabled. On macOS it uses CGL; on Windows or Linux it uses a hidden GLFW OpenGL 3.3 core context (`python -m pip install glfw`). The Windows path is a driver compile check and still needs an actual Iris/Minecraft run for visual and frame-time measurements. Compatibility inputs are bridged to core inputs for the test, and injected DH texture helpers are stubbed; this does not reproduce Iris's complete transformation pipeline.

GPU image checks exercise the real DOF/tone-map fragment program with known focus, background and hand-mask depths, then test translucent particle intersections, the soft-particle off switch and weather opacity. POM GPU fixtures check known flat/sloped height intersections, opposite view directions, atlas isolation, gradual distance fading and bypass conditions. Use `python3 tools/validate.py --static` for configuration checks without an OpenGL context, or `python3 tools/validate.py --images-only` to rerun GPU fixtures without the complete compile matrix. `tools/ValidateShaders.java` is an older validator and does not cover the current profiles.

Before publishing, verify in Minecraft: every profile in the same loaded scene, day/night/rain, close foliage, transparent particles at walls and water, autofocus transitions, underwater views, Nether, End and DH chunk boundaries. Record median and 95th-percentile frame time at a fixed resolution and render distance. Current automated checks do not establish in-game FPS or visual quality across these scenes.

Implementation references: [Iris program ordering](https://shaders.properties/current/reference/shadersproperties/ordering/), [Iris PBR textures](https://shaders.properties/current/how-to/pbr_standards/), [LabPBR data format](https://shaderlabs.org/wiki/LabPBR_Material_Standard), and [Iris buffer format declarations](https://shaders.properties/current/guides/your-first-shaderpack/3_deferred_lighting/).
