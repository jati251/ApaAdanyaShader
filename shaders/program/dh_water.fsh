#include "/lib/common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/environment.glsl"
#include "/lib/water.glsl"

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

in vec2 texcoord, lmcoord;
in vec4 glcolor;
in vec3 viewNormal, viewPos, worldPos;

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 materialData;

void main(){
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
    if (length(viewPos) < 24.0) discard;

    float vanillaSolidDepth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;
    float vanillaWaterDepth = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r;
    if (vanillaSolidDepth < 0.999999 || vanillaWaterDepth < 0.999999) discard;

    vec3 V = normalize(-viewPos);

    float crest;
    vec2 slope=waterSlope(worldPos.xz,dFdx(worldPos.xz),dFdy(worldPos.xz),crest);
    vec3 base=worldDirection(normalize(viewNormal));
    vec3 nw=normalize(base+vec3(-slope.x,0.0,-slope.y)*smoothstep(0.65,0.95,abs(base.y)));
    vec3 N=normalize(mat3(gbufferModelView)*nw)*(gl_FrontFacing?1.0:-1.0);

    // Robust sky light retrieval regardless of Iris transformer coordinate packing
    float skyLight = clamp(max(lmcoord.x, lmcoord.y), 0.0, 1.0);

    // Physical Fresnel reflectance matching vanilla water
    float NdotV = sat(dot(N, V));
    float fresnel = waterFresnel(NdotV,isEyeInWater==1);

    // Environment reflections (sky & clouds) matching vanilla water
    vec3 R = reflect(-V, N);
    vec3 skyReflect = environmentRadiance(worldDirection(R)) * pow(skyLight, 2.0);

    // Direct sun / moon specular highlight matching vanilla water
    vec3 L = normalize(shadowLightPosition);
    vec3 glint = specularBRDF(N, V, L, filteredRoughness(N,WATER_ROUGHNESS), vec3(0.0204)) * lightColor() * skyLight * cloudShadow(worldPos);

    vec3 deepWater = vec3(0.005, 0.038, 0.12) * mix(0.12, 1.0, daylight()) * (0.2 + skyLight * 0.8);
    vec3 waterResult = mix(deepWater, skyReflect, fresnel) + glint;

    color = vec4(max(waterResult, vec3(0.0)), 1.0);
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    materialData = vec4(WATER_ROUGHNESS, skyLight, 0.0, 0.25);
}
