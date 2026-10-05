# Validation — 5 October 2026

The latest retained output is `artifacts/validation.log`. Validation runs on the native NVIDIA GeForce RTX 3080 Ti driver. The current preset update checks all ten profiles and their saved exports, legal option values, complete Indonesian/English names and descriptions, unique translation keys, dimension entry points and Iris clear-color directive syntax.

The latest GPU run passed **750 compiled/linked program variants** and all GPU fixtures. It compiles the five affected entry points (`gbuffers_terrain`, `deferred2`, `deferred3`, `deferred4`, `composite5`) across quality/manual/FSR/active-instance variants, three dimensions and DH enabled/disabled, then executes all synthetic fixtures. Earlier renderer validation compiled 5,100 complete-pipeline variants; intermediate logs from those iterations have been removed during cleanup.

GPU fixtures cover material conductors and linear F0, emission/missing-map defaults, ambient-only AO, contact-shadow penumbra growth, exposure bounds/adaptation/reset, indirect depth/normal rejection, POM, water Fresnel/TIR/rough reflections, cloud bounds, ray refinement, DH frame order, temporal HDR, lens effects, particles and FSR. Preset-only changes do not alter the previously validated shader algorithms.

Runtime diagnosis: the 22:14:41 instance log traced `Index 1 out of bounds for length 1` to `colortex15ClearColor=vec4(0.0)`. GLSL accepted that constructor but Iris' directive parser required four components. It now uses four explicit zeros, and static validation rejects scalar clear-color constructors.

Compatibility builtins and DH sampling helpers are bridged/stubbed in the test harness. Native compilation and fixture results do not establish final Iris bindings, visual appearance, frame time, weather/dimension transitions, resize behavior or memory usage. Reload in Minecraft for runtime verification. In-game visual and performance signoff remains unverified.
