# Realism update — 5 October 2026

Target: Minecraft Java 26.3, Iris 1.11.7, Sodium 0.9.2. Main performance target is Windows with RTX 3080 Ti; macOS remains supported through GLSL 330 / OpenGL. AC4 and RDR2 are artistic references, not source code or engines used by this pack. This update does not claim an identical result.

## Use on Windows or Mac

Copy `ApaAdanyaShader.zip` to the destination instance's `shaderpacks` folder and `ApaAdanyaEffects.zip` to `resourcepacks`. Select the shader, then choose a profile in Shader Pack Settings. Enable the effects resource pack above other texture packs. The effects pack targets resource format 97.1 (Minecraft 26.3).

| Profile | Rendering | Tracing and effects |
| --- | --- | --- |
| Realism (Optimized) | Native resolution | 32 reflection steps, 4 GI rays, 22 cloud steps, 2048 shadows, half-resolution GI and clouds |
| Realism + FSR Ultra Quality | 77% internal width and height | Same effects; AMD FSR 1 EASU and RCAS reconstruct the display image |
| Realism + High Screen-Space Tracing | Native resolution | 48 reflection steps, 6 GI rays, 24 cloud steps, 8 shadow taps |

Start with Realism. At 1440p/4K, compare Realism + FSR Ultra Quality in the same scene. Quality and Balanced FSR modes are also available in Performance & Reconstruction. These are comparison starting points, not measured RTX 3080 Ti FPS promises. DOF and motion blur can be enabled separately after choosing a profile.

The running game has saved Realism + FSR Ultra Quality settings. Its current resource selection is still vanilla: enable ApaAdanyaEffects from Options → Resource Packs, then place it above other packs. Changing options.txt externally while the game is running is not reliable because Minecraft rewrites it. Previous instance settings are backed up under `.codex-backups/visual-upgrade-20261005` in the instance root. No CPU, render-distance, Java allocation, Distant Horizons or OS setting was reduced for the development Mac.

## Implemented

- Shared near/Distant Horizons water spectrum with analytic gradients, gravity-based wave speeds, rain response, and pixel-footprint filtering. The `WATER_OCTAVES` option now changes actual work. Waterfalls retain the mesh orientation. Waves shade the existing mesh; they do not add ocean geometry or change Minecraft's simulation.
- Refraction validates the selected depth before sampling scene color, including DH depth. Removed three-channel dispersion that leaked foreground colors. Caustics follow the submerged scene position. Underwater total internal reflection uses Snell's critical angle.
- Deep-water whitecaps evaluate independently of shoreline foam. Sun highlights use the filtered BRDF rather than adding a second unfiltered glitter lobe.
- Cloud density uses a three-dimensional body with edge erosion, weather coverage, directional extinction and approximate multiple scattering. Density and ray intersections use consistent bounds. Camera-dependent density curvature and skipped sample intervals were removed.
- An eight-step cloud render in the small sky cache supplies cloud reflections to water and reflective materials. The cache's azimuth seam interpolates periodically. Camera cloud history uses matching wind and signed plane intersection above the layer.
- Fire and soul-fire block IDs receive animated HDR radiance. Actual lightning uses a dedicated Iris program and entity ID; flash illumination reaches exposed surfaces, clouds and particles. Arbitrary white/orange/cyan particles no longer become lightning/fire based on color. Removed per-vertex 48-block particle clipping, which could cut stretched quads and unrelated geometry.
- 35 original procedural textures replace animated fire/soul fire, flame particles, smoke, rain and splashes. Smoke uses separate texture references so unrelated generic particles retain their original assets. Rebuild via `python3 tools/build_effects_pack.py <resourcepack-directory>` (NumPy and Pillow).
- Fixed reversed-edge `smoothstep` in puddle ripples and made underwater caustics obey their toggle. Screen-space ray hits refine crossed surfaces even when a coarse step overshoots; rejected silhouette intersections no longer terminate the entire ray.

## Upscaling, ray tracing and frame generation

| Feature | Status in this pack |
| --- | --- |
| FSR 1 EASU + RCAS | Implemented, native / Ultra Quality / Quality / Balanced. GPU fixtures cover all three scaled modes. |
| Reflection ray tracing (SSR) | Implemented software ray marching against the visible depth buffer. |
| Indirect-light tracing (SSGI) | Implemented screen-space diffuse rays, optional half-resolution reconstruction. |
| Hardware RTX / DXR / Vulkan RT / full path tracing | Not implemented. Requires acceleration structures and a renderer integration outside this portable GLSL 330 pipeline. |
| DLSS Super Resolution / Ray Reconstruction | Not integrated. RTX 3080 Ti supports these NVIDIA features, but hardware capability alone does not provide Minecraft/Iris integration. |
| Frame generation | Not implemented. Requires a renderer/presentation integration, frame pacing and reliable motion inputs. |

Research checked 5 October 2026: NVIDIA's [hardware table](https://www.nvidia.com/en-eu/geforce/technologies/dlss/) lists Super Resolution and Ray Reconstruction on RTX 30, but does not list DLSS Frame Generation on that series. [Super Resolution 0.8.3-alpha.5](https://github.com/IReallyWantToSleep/superresolution/releases/tag/0.8.3-alpha.5) documents Minecraft 26.2 with the OpenGL backend; a matching 26.3 build was not verified, so it was not installed. [DLSSmc](https://github.com/lukeclaw/dlssmc) targets 26.3 snapshot 3 with the Vulkan renderer and labels frame generation as tuning; that is not a verified drop-in integration for this instance.

Do not enable the pack's FSR scaling and another resolution scaler simultaneously. No DLSS/FSR2/FSR3/frame-gen setting is exposed as if it worked when there is no backend.

## Validation and limits

Run `python3 tools/validate.py`. The suite compiles and links every profile, dimension and DH variant on the local OpenGL driver, then renders regression fixtures. New fixtures check Fresnel, total internal reflection, deep whitecaps, wave filtering/animation, cloud bounds and visibility above/below the layer, reflected clouds and coarse ray intersections. Existing temporal, FSR, POM, lens and particle fixtures are retained.

`artifacts/sky-cache-preview.png` is a synthetic low-resolution environment-cache render, and `effects-preview.png` is a texture contact sheet. Neither is an in-game screenshot or a photorealism acceptance test.

Windows driver behavior, complete Iris bindings and final RTX 3080 Ti frame times still need in-game validation. Compare settled daylight, sunset, night, rain, underwater, waterfall, shoreline, DH boundaries and moving entities at a fixed output resolution. SSR/SSGI cannot see off-screen geometry. Terrain still needs a compatible PBR resource pack for relief; the supplied effects pack does not replace all world materials. Particle simulation, Minecraft block silhouettes and lightning mesh topology remain Minecraft's.
