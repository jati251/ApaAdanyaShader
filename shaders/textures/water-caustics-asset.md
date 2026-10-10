# Water caustics intensity asset

- Output: `water_caustics_v1.png` (opaque grayscale intensity, original generated PNG).
- Created: 10 October 2026, built-in image_gen tool through the imagegen skill.
- Source file retained at `C:/Users/jatis/.codex/generated_images/01a12685-dd2d-7ee0-b01b-148e96f4976e/exec-f25bd4ce-d368-4959-95a9-fce4e135616a.png`.
- Used by `lib/water_caustics.glsl`, sampled as an intensity mask rather than water color or a normal map.
- Iris binds `aaWaterCaustics` through `customTexture` in `shaders.properties`. Bilinear filtering and clamping use the adjacent `.mcmeta` file: [Iris custom texture documentation](https://shaders.properties/current/reference/buffers/custom_textures/).
- Shader-side mirrored continuation handles edge mismatch without altering the image. Two slowly advected, differently oriented fields animate the pattern; four taps per field and footprint fading limit unresolved detail. Receiver/depth/shadow handling remains in the water and underwater programs.
- Visual asset inspected. Shader compilation, game appearance and FPS are untested at the user's request. This is an artist-generated focus mask, not a physically simulated caustics sequence. Iris is required for the texture; other loaders omit caustics.

## Final generation prompt

Use case: photorealistic-natural. Asset type: production grayscale water-caustics intensity texture for a real-time Minecraft shader, square 1024x1024, opaque. Generate ONLY a flat orthographic overhead seamless tileable texture of physically plausible sunlight caustics from calm shallow river water. Black and dark charcoal field with a fine irregular interconnected network of delicate broken pale gray light filaments, tiny brighter focused junctions, soft wispy gradients. Many small irregular cells, approximately 25 to 35 across the image, with wide variation in cell shape and filament width; no thick constant-width strokes. Focus lines merge, fork, and dissolve naturally. Some quiet open dark areas; neutral grayscale only, balanced distribution across the tile. Continuous matching left-right and top-bottom edges for repeating. No perspective, no water-surface reflections, no ripples drawn as rings, no riverbed stones, no colored water, no objects, no text, no frame, no watermark. Avoid snake-like ribbons, maze paths, isolated loops, repeating sine-wave contours, regular lattices, bold white outlines, hard polygonal cells. This is a lighting intensity mask, not a photo of a landscape. Background must be fully opaque.
