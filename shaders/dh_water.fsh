#version 330 compatibility

#include "/lib/common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/environment.glsl"

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
    float vanillaSolidDepth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;
    float vanillaWaterDepth = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r;
    if (vanillaSolidDepth < 0.999999 || vanillaWaterDepth < 0.999999) discard;

    vec3 V = normalize(-viewPos);

    // Highly optimized analytic animated waves for distant water
    vec2 p = worldPos.xz;
    float t = frameTimeCounter * 1.5;
    vec2 slope = vec2(
        cos(p.x * 0.40 + p.y * 0.20 - t) * 0.035 + cos(p.x * 0.85 - p.y * 0.45 + t * 1.3) * 0.018,
        sin(p.x * 0.25 - p.y * 0.35 + t) * 0.035 + sin(p.x * 0.60 + p.y * 0.75 - t * 0.9) * 0.018
    ) * WATER_WAVES;

    vec3 nw = normalize(vec3(-slope.x, 1.0, -slope.y));
    vec3 N = normalize(mat3(gbufferModelView) * nw);

    // Physical Fresnel reflectance
    float NdotV = sat(dot(N, V));
    float fresnel = 0.0204 + 0.9796 * pow(1.0 - NdotV, 5.0);

    // Environment reflections (sky & clouds)
    vec3 R = reflect(-V, N);
    vec3 skyReflect = environmentRadiance(worldDirection(R)) * pow(lmcoord.y, 2.0);

    // Direct sun / moon specular highlight
    vec3 L = normalize(shadowLightPosition);
    float NdotL = sat(dot(N, L));
    vec3 glint = specularBRDF(N, V, L, WATER_ROUGHNESS, vec3(0.0204)) * lightColor() * NdotL * lmcoord.y;

    // Deep ocean water scattering
    vec3 deepWater = vec3(0.008, 0.060, 0.088) * mix(0.12, 1.0, daylight()) * lmcoord.y;
    vec3 waterColor = mix(deepWater, skyReflect, fresnel) + glint;

    // Distance atmospheric fog blend: seamlessly unites DH water with horizon sky
    float dist = length(viewPos);
    vec3 rd = worldDirection(-V);
    vec3 fog = skyRadiance(normalize(vec3(rd.x, 0.035, rd.z)));
    float fogAmount = 1.0 - exp(-dist * 0.00028 * FOG_DENSITY);
    waterColor = mix(waterColor, fog, fogAmount);

    color = vec4(waterColor, mix(0.85, 1.0, fresnel));
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    materialData = vec4(WATER_ROUGHNESS, lmcoord.y, 0.0, 0.0);
}
