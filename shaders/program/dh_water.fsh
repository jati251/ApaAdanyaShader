#include "/lib/common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/environment.glsl"
#include "/lib/water.glsl"

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D dhDepthTex1,colortex6;
uniform mat4 dhProjectionInverse;

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
    vec2 uv=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
    if (dot(viewPos,viewPos) < 576.0) discard;

    // Vanilla water draws afterwards; only opaque vanilla terrain exists here.
    float vanillaSolidDepth = depthScreen(depthtex1,uv);
    if (vanillaSolidDepth < 0.999999 &&
        viewDepth(uv,vanillaSolidDepth)>viewPos.z+0.02) discard;

    vec3 V = normalize(-viewPos);

    float crest;
    vec2 slope=waterSlope(worldPos.xz,dFdx(worldPos.xz),dFdy(worldPos.xz),crest);
    vec3 base=worldDirection(normalize(viewNormal));
    vec3 nw=normalize(base+vec3(-slope.x,0.0,-slope.y)*smoothstep(0.65,0.95,abs(base.y)));
    vec3 N=normalize(mat3(gbufferModelView)*nw)*(gl_FrontFacing?1.0:-1.0);
    // Smooth grazing clamp: prevents 180-degree normal inversion flicker on low camera angles
    float ndotv=dot(N,V);
    if(ndotv < 0.01) {
        N=normalize(N+V*(0.01-ndotv));
    }

    // Robust sky light retrieval regardless of Iris transformer coordinate packing
    float skyLight = clamp(lmcoord.y, 0.0, 1.0);

    // Physical Fresnel reflectance matching vanilla water
    float NdotV = dot(N, V);
    float fresnel = waterFresnel(NdotV,isEyeInWater==1);

    // Environment reflections (sky & clouds) matching vanilla water
    vec3 meshN = normalize(viewNormal);
    vec3 R = reflect(-V, N);
    if(dot(R, meshN) < 0.02) R = normalize(R + meshN * (0.02 - dot(R, meshN)));
    float skyExposure=isEyeInWater==1?smoothstep(8.0,180.0,float(eyeBrightnessSmooth.y)):skyLight;
    vec3 skyReflect = environmentRadiance(worldDirection(R)) * skyExposure*skyExposure;

    // Direct sun / moon specular highlight matching vanilla water
    vec3 L = normalize(shadowLightPosition);
    float footprint=max(length(dFdx(worldPos.xz)),length(dFdy(worldPos.xz)));
    float roughness=filteredRoughness(N,sqrt(WATER_ROUGHNESS*WATER_ROUGHNESS
        +0.012*smoothstep(0.15,2.0,footprint)));
    vec3 glint = specularBRDF(N, V, L, roughness, vec3(0.0204)) * lightColor() * skyLight * cloudShadow(worldPos);

    float bottom=depthScreen(dhDepthTex1,uv);
    float thickness=80.0;
    if(bottom<0.999999) {
        vec4 p=dhProjectionInverse*vec4(uv*2.0-1.0,bottom*2.0-1.0,1.0);
        thickness=clamp(length(p.xyz/p.w-viewPos),0.0,80.0);
    }
    vec3 transmittance=isEyeInWater==1?vec3(1.0):exp(-waterAbsorption()*thickness);
    vec3 body=textureScreen(colortex6,uv).rgb*transmittance
        +waterBodyColor(thickness,skyLight)*(1.0-transmittance);
    vec3 waterResult = mix(body, skyReflect, fresnel) + glint;

    color = vec4(max(waterResult, vec3(0.0)), 1.0);
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    materialData = vec4(WATER_ROUGHNESS, skyLight, 0.0, 0.25);
}
