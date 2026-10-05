# Validation, 5 October 2026

Environment: Apple M1, native macOS OpenGL driver. Commands: `python3 tools/validate.py` for the complete compile matrix; `python3 tools/validate.py --images-only` for the final image checks after correcting the test harness texture-upload binding. No production GLSL changed between those checks.

- PASS: six complete profiles with legal setting values and English/Indonesian labels.
- PASS: boolean options have Iris-discoverable conditional checks; dimension entry points are complete.
- PASS: 1,584 program variants compiled and linked: 24 programs across three dimensions, eleven configurations, and DH enabled/disabled.
- PASS: GPU image test keeps the focus plane and hand pixels within 0.00001 of the sharp reference.
- PASS: background image variance falls from 0.10427 to below 0.00001 under DOF in the synthetic fixture; manual focus and autofocus agree within 0.005.
- PASS: GPU particle test checks zero opacity at intersection, half opacity midway through the fade, full opacity in free space, the disabled-effect path, and weather opacity 0.65.
- PASS: GPU POM checks flat, constant and sloped height fields; opposite tangent-view directions; adjacent-atlas isolation; distance fading; and head-on, grazing, zero-depth and invalid-bounds bypass.
- PASS: POM compiles with normal maps disabled, specular maps disabled and depth set to zero.
- PASS: `git diff --check`.

The compile harness translates compatibility builtins to core inputs and stubs DH texture helpers. GPU fixtures use synthetic textures/depths; they exercise shader output but do not validate Minecraft texture bindings, draw order or the complete Iris transformation pipeline.

In-game visual review and FPS/frame-time benchmarking remain pending. Minecraft's Java window was not exposed through the available native-app control interface. The running game's saved shader-option overrides were not changed, and the pack has not been reloaded through the game in this task.

POM adds terrain texture relief only. Resource-pack compatibility, model UV behavior and frame times still require in-game checks. The instance resourcepacks directory contained no files when inspected.
