#include "/lib/common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/environment.glsl"
#include "/lib/trace.glsl"
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif
uniform sampler2D gtexture,colortex6,depthtex1;
uniform float alphaTestRef;
in vec2 texcoord,lmcoord;
in vec4 glcolor;
in vec3 viewNormal,viewPos,worldPos;
in vec4 tangent;
flat in float materialId;
/* RENDERTARGETS: 0,2 */
layout(location=0) out vec4 color;
layout(location=1) out vec4 materialData;

// Assassin's Creed IV Caribbean Wave Spectrum (Vectorized multi-scale Gerstner waves)
const vec4 waveDirX1 = vec4( 0.816, -0.707,  0.383, -0.966);
const vec4 waveDirZ1 = vec4( 0.578,  0.707, -0.924, -0.259);
const vec4 waveFreq1 = vec4( 0.350,  0.620,  1.150,  2.100);
const vec4 waveAmp1  = vec4( 0.085,  0.052,  0.030,  0.018);
const vec4 waveSpd1  = vec4( 1.100,  1.450,  1.950,  2.600);

const vec4 waveDirX2 = vec4( 0.643, -0.174,  0.940, -0.500);
const vec4 waveDirZ2 = vec4(-0.766,  0.985,  0.342, -0.866);
const vec4 waveFreq2 = vec4( 3.600,  5.800,  9.500, 15.000);
const vec4 waveAmp2  = vec4( 0.010,  0.006,  0.003,  0.002);
const vec4 waveSpd2  = vec4( 3.400,  4.500,  5.800,  7.500);

vec3 waterNormal(out float waveCrest){
    vec2 p = worldPos.xz;
    float time = frameTimeCounter;
    float dist = length(viewPos);
    // Smooth distance attenuation to eliminate far moire shimmer while keeping crisp near waves
    float distFade = clamp(1.0 - dist * 0.0022, 0.15, 1.0);
    float wavesScale = WATER_WAVES * distFade;

    // Pass 1: Primary Caribbean ocean swell & peaked cross-seas
    vec4 dotP1 = p.x * waveDirX1 + p.y * waveDirZ1;
    vec4 phase1 = dotP1 * waveFreq1 - time * waveSpd1;
    vec4 sinP1 = sin(phase1);
    vec4 cosP1 = cos(phase1);
    vec4 sharpCrest1 = exp(sinP1 - vec4(1.0));
    vec4 slopeFactor1 = cosP1 * sharpCrest1 * (waveAmp1 * wavesScale * waveFreq1);

    vec2 slope = vec2(
        dot(slopeFactor1, waveDirX1),
        dot(slopeFactor1, waveDirZ1)
    );

    // Pass 2: Wind chop and micro-capillary liquid ripples
    vec4 dotP2 = p.x * waveDirX2 + p.y * waveDirZ2;
    vec4 phase2 = dotP2 * waveFreq2 - time * waveSpd2;
    vec4 sinP2 = sin(phase2);
    vec4 cosP2 = cos(phase2);
    vec4 sharpCrest2 = exp(sinP2 - vec4(1.0));
    vec4 slopeFactor2 = cosP2 * sharpCrest2 * (waveAmp2 * wavesScale * waveFreq2);

    slope += vec2(
        dot(slopeFactor2, waveDirX2),
        dot(slopeFactor2, waveDirZ2)
    );

    waveCrest = dot(sharpCrest1, vec4(0.40, 0.30, 0.20, 0.10));

    // True physical height-gradient normal mapping with rich 3D relief
    vec3 nw = normalize(vec3(-slope.x * 2.2, 1.0, -slope.y * 2.2));
    return normalize(mat3(gbufferModelView) * nw) * (gl_FrontFacing ? 1.0 : -1.0);
}

void main(){
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
    materialData=vec4(WATER_ROUGHNESS,lmcoord.y,0.0,0.25);
    vec4 tex=texture(gtexture,texcoord)*glcolor;
    if(tex.a<0.001) discard;
    if(abs(materialId-1003.0)>0.5){
        vec3 albedo=pow(max(tex.rgb,vec3(0.0)),vec3(2.2));
        color=vec4(shadeSurface(albedo,normalize(viewNormal),viewPos,lmcoord,0.24,0.0,0.0,vec3(0.04)),tex.a); return;
    }
    vec2 screenUV=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
    float waveCrest=0.0;
    vec3 N=waterNormal(waveCrest),V=normalize(-viewPos),R=reflect(-V,N);
    float opaqueDepth=textureScreen(depthtex1,screenUV).r;
    vec3 behind=viewPosition(screenUV,opaqueDepth);
    #ifdef DISTANT_HORIZONS
    if(opaqueDepth>=0.999999){
        float dhD=textureScreen(dhDepthTex0,screenUV).r;
        if(dhD<1.0){
            vec4 clipDH=vec4(screenUV*2.0-1.0,dhD*2.0-1.0,1.0);
            vec4 vpDH=dhProjectionInverse*clipDH;
            behind=vpDH.xyz/vpDH.w;
        }
    }
    #endif
    float thickness=min(length(behind-viewPos),80.0);

    #ifdef WATER_REFRACTION
    // Liquid optical refraction with subtle chromatic dispersion
    vec2 refrDelta = N.xy * min(thickness, 2.8) * 0.0036;
    vec2 refractUV = clamp(screenUV + refrDelta, vec2(0.001), vec2(0.999));
    float refractDepth = textureScreen(depthtex1, refractUV).r;
    vec3 refractPos = viewPosition(refractUV, refractDepth);
    if(refractPos.z > viewPos.z + 0.05) {
        refractUV = screenUV;
    } else {
        thickness = min(length(refractPos - viewPos), 80.0);
    }
    // Chromatic dispersion across wave refraction boundaries
    vec3 transmitted;
    transmitted.r = textureScreen(colortex6, clamp(refractUV - refrDelta * 0.16, vec2(0.001), vec2(0.999))).r;
    transmitted.g = textureScreen(colortex6, refractUV).g;
    transmitted.b = textureScreen(colortex6, clamp(refractUV + refrDelta * 0.16, vec2(0.001), vec2(0.999))).b;
    #else
    vec2 refractUV = screenUV;
    vec3 transmitted = textureScreen(colortex6, refractUV).rgb;
    #endif

    // AC4 Caribbean Sea Absorption & Transmittance (Beer-Lambert Law)
    vec3 absorption = vec3(0.24, 0.048, 0.016) / WATER_CLARITY;
    vec3 transmittance = exp(-absorption * thickness);

    // Caribbean Gradient: Crystal Turquoise Shallows -> Deep Oceanic Sapphire
    float day = daylight();
    vec3 deepWater = vec3(0.005, 0.038, 0.12) * mix(0.12, 1.0, day) * (0.2 + lmcoord.y * 0.8);
    vec3 shallowWater = vec3(0.02, 0.28, 0.36) * mix(0.15, 1.0, day) * (0.25 + lmcoord.y * 0.75);
    vec3 waterColor = mix(shallowWater, deepWater, smoothstep(1.5, 16.0, thickness));

    transmitted = transmitted * transmittance + waterColor * (1.0 - transmittance);

    // Forward Subsurface Scattering (In-Scatter: sunlight penetrating translucent wave crests)
    #if !defined(NETHER) && !defined(END)
    vec3 L = normalize(shadowLightPosition);
    float sunScatterLobe = pow(sat(dot(V, -L)), 4.0) * 0.70 + pow(sat(dot(V, -L) * 0.5 + 0.5), 2.0) * 0.30;
    vec3 sssColor = vec3(0.02, 0.46, 0.42);
    vec3 waveSSS = sssColor * lightColor() * sunScatterLobe * (1.0 - transmittance.g) * min(thickness, 4.0) * 0.14 * lmcoord.y;
    transmitted += waveSSS;
    #endif

    #ifdef WATER_CAUSTICS
    // Focused Dual-Interference Prism Caustics on submerged surfaces
    vec2 cPos = worldPos.xz;
    float ct = frameTimeCounter * 1.6;
    float caustA = sin(cPos.x * 2.2 + cPos.y * 1.6 + ct * 1.4);
    float caustB = cos(cPos.x * 1.8 - cPos.y * 2.3 - ct * 1.2);
    float caustC = sin(cPos.x * 3.6 + cPos.y * 1.1 + ct * 2.1);
    float causticWave = pow(sat(1.0 - abs(caustA + caustB) * 0.5), 5.0) * 0.7 + pow(sat(1.0 - abs(caustB + caustC) * 0.5), 4.0) * 0.3;
    vec3 caustColor = vec3(0.04, 0.14, 0.16) * causticWave * exp(-thickness * 0.28) * day * lmcoord.y;
    transmitted += caustColor;
    #endif

    vec3 reflected = environmentRadiance(worldDirection(R)) * pow(lmcoord.y, 2.0);
    #ifdef SSR
    vec2 hit;
    if(traceScreen(depthtex1, viewPos + N * 0.08, R, 0.22, SSR_STEPS, hit)) {
        vec3 ssrColor = textureScreen(colortex6, hit).rgb;
        if(WATER_ROUGHNESS > 0.08) {
            float rOffset = WATER_ROUGHNESS * 0.004;
            ssrColor = ssrColor * 0.60 + 0.20 * (textureScreen(colortex6, hit + vec2(rOffset, 0.0)).rgb + textureScreen(colortex6, hit - vec2(rOffset, 0.0)).rgb);
        }
        reflected = mix(reflected, ssrColor, edgeFade(hit));
    }
    #endif

    // Physical Schlick Fresnel with brewster water boundary
    float fresnel = 0.0204 + 0.9796 * pow(1.0 - sat(dot(N, V)), 5.0);
    if(isEyeInWater == 1) fresnel = mix(fresnel, 1.0, smoothstep(0.70, 0.76, 1.0 - dot(N, V) * dot(N, V)));

    // Ocean Sun & Moon Glitter: physically based specular with anisotropic diamond glints
    vec3 glint = vec3(0.0);
    #if !defined(NETHER) && !defined(END)
    float nl = dot(N, L);
    if(nl > 0.001 && lmcoord.y > 0.05){
        float vis = shadowVisibility(worldPos - cameraPosition, worldDirection(N), nl, true);
        if(vis > 0.001){
            vec3 specular = specularBRDF(N, V, L, filteredRoughness(N, WATER_ROUGHNESS), vec3(0.0204)) * lightColor() * vis * lmcoord.y * cloudShadow(worldPos);

            // Daytime golden solar glitter
            float sunGlitter = pow(sat(dot(reflect(-L, N), V)), 140.0) * 0.55 * vis * daylight();
            // Nighttime silvery lunar ocean glitter path (AC4 Night Ocean Look)
            float moonGlitter = pow(sat(dot(reflect(-L, N), V)), 180.0) * 2.20 * vis * (1.0 - daylight()) * NIGHT_BRIGHTNESS;
            vec3 glitterCol = mix(vec3(0.35, 0.55, 0.85) * moonGlitter, vec3(sunGlitter), daylight());

            glint = specular + glitterCol;
        }
    }
    #endif

    vec3 result = mix(transmitted, reflected, fresnel) + glint;

    #ifdef WATER_FOAM
    // 1. Lush Organic Shoreline Foam with dynamic wave surge wash-up
    float waveSurge = sin(worldPos.x * 0.45 + worldPos.z * 0.30 + frameTimeCounter * 1.8) * 0.12;
    float shoreBand = 1.0 - smoothstep(0.01, 0.55 + waveSurge, thickness);
    if(shoreBand > 0.001){
        float shoreNoise1 = noise3D(worldPos * 3.8 + vec3(frameTimeCounter * 0.35, 0.0, frameTimeCounter * 0.25));
        float shoreNoise2 = noise3D(worldPos * 8.0 - vec3(frameTimeCounter * 0.20, 0.0, frameTimeCounter * 0.15));
        float froth = shoreNoise1 * 0.60 + shoreNoise2 * 0.40;
        float shoreFoam = smoothstep(0.30, 0.68, froth + shoreBand * 0.60) * shoreBand;

        // 2. Open Ocean Whitecaps (Foam peaking on steep rolling wave crests)
        float oceanWhitecap = smoothstep(0.68, 0.92, waveCrest) * WATER_WAVES * smoothstep(1.5, 4.0, thickness) * 0.42;

        float totalFoam = clamp(shoreFoam + oceanWhitecap, 0.0, 1.0);
        vec3 foamColor = vec3(0.88, 0.93, 0.95) * mix(0.25, 1.0, daylight()) * (0.35 + lmcoord.y * 0.65);
        result = mix(result, foamColor, totalFoam * 0.88);
    }
    #endif

    color = vec4(max(result, vec3(0.0)), 1.0);
}



