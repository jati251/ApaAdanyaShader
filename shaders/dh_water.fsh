#version 330 compatibility

#include "/lib/common.glsl"
#include "/lib/lighting.glsl"

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

in vec2 texcoord, lmcoord;
in vec4 glcolor;
in vec3 viewNormal, viewPos, worldPos;

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 materialData;

void main() {
    // Prevent DH LOD water from rendering near player or overlapping with vanilla trees/terrain/water
    if (length(viewPos) < 24.0) discard;

    float vanillaSolidDepth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;
    float vanillaWaterDepth = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r;
    if (vanillaSolidDepth < 0.999999 || vanillaWaterDepth < 0.999999) discard;

    vec4 tex = glcolor;
    #ifdef DISTANT_HORIZONS
    if (dh_hasTexture()) {
        tex *= dh_sampleTexture();
    }
    #endif
    vec3 albedo = vec3(0.012, 0.065, 0.11) * daylight();
    vec3 N = normalize(viewNormal);
    float roughness = 0.08;

    vec3 shaded = shadeSurface(albedo, N, viewPos, lmcoord, roughness, 0.0, 0.0, vec3(0.02));

    color = vec4(shaded, 0.82);
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    materialData = vec4(roughness, lmcoord.y, 0.0, 0.0);
}
