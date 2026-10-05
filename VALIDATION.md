# Validation, 5 October 2026

The complete check was run on an Apple M1 with the macOS OpenGL driver:

```sh
python3 tools/validate.py
```

Results:

- 20 configurations compiled and linked with Distant Horizons enabled and disabled: **3,840 program variants**.
- Profile completeness, legal option values, both translations, boolean option discovery and all dimension entry points passed.
- GPU lens fixture passed: focus plane and hand preservation, autofocus/manual focus agreement, and background variance reduced from `0.10427` to `0.00053`.
- GPU particle fixture passed: intersection, midpoint, free-space alpha, disabled effect and weather opacity.
- GPU temporal fixture passed: HDR history, motion reprojection, depth rejection, camera cuts and hand rejection.
- GPU FSR 1 fixtures passed for all three modes on an odd `97x55` viewport: EASU/RCAS constant-color preservation, black/white edges and unused-region isolation.
- GPU POM fixture passed: flat, constant and sloped heights, ray direction, atlas isolation, distance fade, grazing/head-on/zero-depth and invalid-bounds bypass.
- `git diff --check` passed.

`python3 tools/validate.py --images-only` reruns the GPU image fixtures without the compile matrix. `python3 tools/validate.py --static` checks settings, profiles, translations and shader entry-point coverage without creating an OpenGL context.

The harness compiles the same GLSL 330 source used for both operating systems. On macOS it uses CGL; on Windows/Linux it uses a hidden GLFW OpenGL 3.3 context (`python -m pip install glfw`). Compatibility builtins are bridged to core inputs and Distant Horizons texture helpers are stubbed. These checks catch shader and math regressions, but they cannot prove the complete Iris patching/binding pipeline.

The fixtures use synthetic textures and depth values. They do not replace an in-game review of Iris framebuffer bindings, resource-pack PBR maps, window resizing, block outlines, translucent geometry, Distant Horizons boundaries or all Minecraft dimensions. The game's Java window was not exposed through the native-app control interface during this run, so no in-game FPS or frame-time number is claimed. Existing shader-option overrides were not changed.

The reduced-resolution implementation keeps framebuffer allocations and uses an active lower-left viewport. It is therefore expected to reduce scene shading work, but the actual gain depends on GPU driver, resolution, render distance, scene complexity and CPU load. Measure native versus each FSR mode in the same settled scene before choosing a default.
