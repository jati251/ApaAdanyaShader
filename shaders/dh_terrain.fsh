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

    vec3 albedo = pow(max(tex.rgb, vec3(0.0)), vec3(2.2));
    vec3 N = normalize(viewNormal);
    float roughness = 0.82;

    vec3 shaded = shadeSurface(albedo, N, viewPos, lmcoord, roughness, 0.0, 0.0, vec3(0.04));

    color = vec4(shaded, 1.0);
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    materialData = vec4(roughness, lmcoord.y, 0.0, 0.0);
}
