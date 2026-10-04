# ApaAdanyaShader

A lightweight yet visually stunning, physically inspired Minecraft shaderpack engineered for **Iris Shaders + Sodium** (and OptiFine) on modern Minecraft (including native Apple Silicon / macOS Metal compatibility).

## Key Highlights & Features
- **Distant Horizons (DH) Support:** 100% seamless color, lighting, ambient, and water matching between near vanilla chunks and distant LODs.
- **5 Tiered Performance Profiles:**
  - **Potato (180+ FPS):** Zero shadow overhead, instant NDC vertex clipping, fast 2D clouds, no raymarching. Perfect for integrated GPUs and low-end laptops.
  - **Low:** Fast single-sample shadows, optimized 2D clouds, smooth performance with crisp shadows.
  - **Medium (Balanced):** Real-time SSR water reflections, 3D volumetric cumulus clouds, contact shadows.
  - **High (Realistic):** SSGI indirect bounce lighting, volumetric god rays, soft penumbra shadows.
  - **Ultra (Showcase):** High-sample SSGI, dense multi-step volumetric raymarching, maximum visual fidelity.
- **Water & Oceans:** Physical Fresnel reflections, animated multi-octave waves, underwater optical absorption/clarity, shoreline foam, and SSR.
- **Sky & Atmosphere:** Dynamic day/sunset/night Rayleigh & Mie atmospheric scattering, celestial corona, procedural stars, and powder-sugar volumetric cloud rendering.
- **Color Grading & Optics:** ACES-Luma chromatic tonemapping, bloom, smart vibrance, filmic contrast, and temporal color dithering.
- **World & Foliage:** Natural wind-swaying foliage, crops, and leaves; rain puddles with wet surface roughness.

## Installation
1. Place the `ApaAdanyaShader` folder into your `.minecraft/shaderpacks/` directory.
2. In Minecraft, navigate to **Options -> Video Settings -> Shader Packs** and select `ApaAdanyaShader`.
3. Choose your preferred profile (Potato, Low, Medium, High, Ultra) in **Shader Pack Settings**.
