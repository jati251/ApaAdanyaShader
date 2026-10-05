#include "/lib/common.glsl"
#include "/lib/lighting.glsl"

uniform sampler2D depthtex0;

in vec2 texcoord, lmcoord;
in vec4 glcolor;
in vec3 viewNormal, viewPos, worldPos;
flat in float materialId;

/* RENDERTARGETS: 0,1,2,15 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 materialData;
layout(location = 3) out vec4 responseData;

void main(){
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
    // Prevent DH LOD terrain from ever overlapping or clipping with near vanilla terrain
    if (length(viewPos) < 24.0) discard;

    // DH terrain runs before vanilla terrain. Its depth is not available here;
    // normal terrain covers this layer later in the frame.

    vec4 tex = glcolor;
    #ifdef DISTANT_HORIZONS
    if (dh_hasTexture()) {
        tex *= dh_sampleTexture();
    }
    #endif
    if (tex.a < 0.1) discard;

    // Linearize texture albedo exactly like vanilla terrain (surface.fsh)
    vec3 albedo = srgbToLinear(tex.rgb);
    vec3 N = normalize(viewNormal);
    float roughness = 0.78;

    // Preserve the separate sky/block channels; sorting loses lamp light in caves.
    // Confirmed from installed DH 3.3.4 packing and Iris 1.11.7 decoding:
    // block is the high nibble (x), sky the low nibble (y).
    float skyLight = clamp(lmcoord.y, 0.0, 1.0);
    float blockLight = clamp(lmcoord.x, 0.0, 1.0);
    vec2 lm = vec2(blockLight, skyLight);

    // Call standard surface shading for 100% mathematical parity with vanilla chunks
    float ambientFraction;
    vec3 shaded = shadeMaterial(albedo, N, viewPos, lm, filteredRoughness(N,roughness), 0.0, 0.0, vec3(0.04),0.0,1.0,ambientFraction);

    color = vec4(shaded, 1.0);
    responseData=vec4(diffuseResponse(albedo,vec3(0.04),0.0),ambientFraction);
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    materialData = vec4(roughness, skyLight, 0.0, 0.0);
}
