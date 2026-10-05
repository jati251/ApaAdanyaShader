# Validation — 5 October 2026

The final source passed `python3 tools/validate.py` on the Apple M1 OpenGL driver. Full output is in `artifacts/validation.log`.

- Nine complete quality profiles; 23 configurations including manual options and FSR variants.
- **4,554 shader program variants compiled and linked**, across three dimensions and Distant Horizons enabled/disabled.
- GPU water fixtures: normal/grazing Fresnel, underwater critical-angle reflection, deep-water whitecaps, animated waves and pixel-footprint filtering.
- GPU cloud fixtures: consistent volume bounds, visibility above/below the layer, finite opacity, and clouds present in the environment-reflection cache.
- GPU ray fixtures: coarse steps refine surface crossings; sky remains a miss.
- Existing lens, soft particle, temporal HDR, FSR EASU/RCAS and POM regressions passed.
- 35 RGBA texture assets verified, including four 32-frame flame strips, smoke references and resource format 97.1.
- `git diff --check` passed.

The instance log shows an Iris reload of ApaAdanyaShader at 20:05 WIB with no shader compilation error in that reload segment. Unused-attribute/link warnings remain. Earlier renderer `Deleting stream buffers: Invalid operation` messages are not diagnosed by these shader tests.

The native automation interface exposes the launcher but not Minecraft's Java game window. No in-game visual signoff or RTX 3080 Ti frame-time measurement was performed. Windows GLSL driver compilation, final Iris bindings, resource-pack activation, framebuffer resize, weather transitions and DH seams still require validation on the destination PC.

The harness bridges compatibility builtins and stubs DH texture helpers. Synthetic renders establish math and shader regressions, not identical AC4/RDR2 visuals. `artifacts/sky-cache-preview.png` is a synthetic low-resolution cache diagnostic; `effects-preview.png` is a texture contact sheet.

Rerun GPU fixtures with `python3 tools/validate.py --images-only`; run the settings/translation/dimension checks with `python3 tools/validate.py --static`.
