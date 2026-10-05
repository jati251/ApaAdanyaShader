# Validation, 5 October 2026

Environment: Apple M1, native macOS OpenGL driver. Commands: `python3 tools/validate.py` for the complete compile matrix; `python3 tools/validate.py --images-only` for the final image checks. The validator selects CGL on macOS and a hidden GLFW OpenGL 3.3 core context on Windows/Linux.

- PASS: six complete profiles with legal setting values and English/Indonesian labels.
- PASS: boolean options have Iris-discoverable conditional checks; dimension entry points are complete.
- PASS: 2,352 program variants compiled and linked: 24 programs across three dimensions, fourteen configurations, and DH enabled/disabled. The matrix includes the full-resolution reference, no-cloud-history and AO-only reconstruction modes.
- PASS: GPU image test keeps the focus plane and hand pixels within 0.00001 of the sharp reference.
- PASS: background image variance falls from 0.10427 to below 0.00001 under DOF in the synthetic fixture; manual focus and autofocus agree within 0.005.
- PASS: GPU particle test checks zero opacity at intersection, half opacity midway through the fade, full opacity in free space, the disabled-effect path, and weather opacity 0.65.
- PASS: GPU POM checks flat, constant and sloped height fields; opposite tangent-view directions; adjacent-atlas isolation; distance fading; and head-on, grazing, zero-depth and invalid-bounds bypass.
- PASS: POM compiles with normal maps disabled, specular maps disabled and depth set to zero.
- PASS: `git diff --check`.

The compile harness translates compatibility builtins to core inputs and stubs DH texture helpers. GPU fixtures use synthetic textures/depths; they exercise shader output but do not validate Minecraft texture bindings, pass ordering or the complete Iris transformation pipeline. Windows/Linux GPU validation additionally requires Python GLFW and a working OpenGL 3.3 driver.

In-game visual review and FPS/frame-time benchmarking remain pending. Minecraft's Java window was not exposed through the available native-app control interface. The running game's saved shader-option overrides were not changed, and the pack has not been reloaded through the game in this task.

The reduced-resolution passes use Iris framebuffer sizes and fragment shaders only, so they do not require Metal compute, CUDA or a Windows-only API. Cloud history rejects camera jumps, weather changes, stale frame tags, invalid samples and large reprojection movement; lighting and DOF fall back to native-resolution samples at depth, normal and focus edges.

POM adds terrain texture relief only. Resource-pack compatibility, model UV behavior and frame times still require in-game checks. The instance resourcepacks directory contained no files when inspected.
