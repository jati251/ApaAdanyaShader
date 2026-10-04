#version 330 compatibility

#include "/lib/common.glsl"
#include "/lib/lighting.glsl"

uniform sampler2D depthtex0;

in vec2 texcoord, lmcoord;
in vec4 glcolor;
in vec3 viewNormal, viewPos, worldPos;
flat in float materialId;

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 materialData;

void main() {
    // Prevent DH LOD terrain from ever overlapping or clipping with near vanilla terrain
    if (length(viewPos) < 24.0) discard;

    float vanillaDepth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;
    if (vanillaDepth < 0.999999) discard;

    vec4 tex = glcolor;
    #ifdef DISTANT_HORIZONS
    if (dh_hasTexture()) {
        tex *= dh_sampleTexture();
    }
    #endif
    if (tex.a < 0.1) discard;

    // Linearize texture albedo exactly like vanilla terrain (surface.fsh)
    vec3 albedo = pow(max(tex.rgb, vec3(0.0)), vec3(2.2));
    vec3 N = normalize(viewNormal);
    float roughness = 0.78;

    // Robust light coordinate handling for Iris DH:
    // DHTerrainTransformer stores SkyLight in .x and BlockLight in .y.
    // Clamping max ensures skyLight is ~0.97 in daylight, perfectly matching vanilla lmcoord.y.
    float skyLight = clamp(max(lmcoord.x, lmcoord.y), 0.0, 1.0);
    float blockLight = clamp(min(lmcoord.x, lmcoord.y), 0.0, 1.0);
    vec2 lm = vec2(blockLight, skyLight);

    // Call standard surface shading for 100% mathematical parity with vanilla chunks
    vec3 shaded = shadeSurface(albedo, N, viewPos, lm, roughness, 0.0, 0.0, vec3(0.04));

    color = vec4(shaded, 1.0);
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    materialData = vec4(roughness, skyLight, 0.0, 0.0);
}
