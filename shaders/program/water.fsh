#include "/lib/common.glsl"
#include "/lib/lighting.glsl"
#include "/lib/fire.glsl"
#include "/lib/environment.glsl"
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjectionInverse;
#define AA_TRACE_DH
#endif
#include "/lib/trace.glsl"
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

#include "/lib/water.glsl"
#include "/lib/water_reflection.glsl"
#include "/lib/scene_trace.glsl"

vec3 waterNormal(vec2 slope){
    vec3 base=worldDirection(normalize(viewNormal));
    vec3 nw=waterSurfaceNormal(base,slope);
    return normalize(mat3(gbufferModelView)*nw)*(gl_FrontFacing?1.0:-1.0);
}

vec3 waterFragmentPosition() {
    return viewPosition(gl_FragCoord.xy/vec2(viewWidth,viewHeight),gl_FragCoord.z);
}

vec3 opaquePosition(vec2 uv,out bool valid) {
    float depth=depthScreen(depthtex1,uv);
    valid=depth<0.999999;
    if(valid) return viewPosition(uv,depth);
    #ifdef DISTANT_HORIZONS
    float dhD=depthScreen(dhDepthTex1,uv);
    if(dhD<1.0){
        valid=true;
        vec4 pos=dhProjectionInverse*vec4(uv*2.0-1.0,dhD*2.0-1.0,1.0);
        return pos.xyz/pos.w;
    }
    #endif
    vec3 surfacePos=waterFragmentPosition();
    return surfacePos+normalize(surfacePos)*80.0;
}

float worldUpDelta(vec3 v) {
    return dot(vec3(gbufferModelViewInverse[0][1], gbufferModelViewInverse[1][1], gbufferModelViewInverse[2][1]), v);
}

bool waterReflectionAboveSurface(vec2 hit,bool underwater,vec3 surfacePos) {
    if(underwater) return true;
    bool valid;
    vec3 position=opaquePosition(hit,valid);
    // Ocean reflection cannot originate from a submerged bed or underwater plant.
    return valid && worldUpDelta(position-surfacePos)>=-0.02;
}

bool waterReflectionAboveSurface(vec2 hit,bool underwater) {
    return waterReflectionAboveSurface(hit,underwater,waterFragmentPosition());
}

vec3 waterReflectionSample(vec2 hit,float roughness) {
    vec3 center=textureScreen(colortex6,hit).rgb;
    if(roughness<=0.08) return center;
    bool centerValid;
    float centerZ=traceSurfaceDepth(depthtex1,hit,centerValid);
    // Project an angular roughness lobe, rather than a nearly one-pixel blur
    // that leaves reflections jagged at native/high display resolutions.
    vec2 radius=max(0.25*roughness*roughness
        *abs(vec2(gbufferProjection[0][0],gbufferProjection[1][1])),
        1.5/vec2(viewWidth,viewHeight));
    const vec2 offsets[4]=vec2[4](vec2(-1,0),vec2(1,0),vec2(0,-1),vec2(0,1));
    vec3 sum=center*0.40;
    float weight=0.40;
    for(int i=0;i<4;i++) {
        vec2 uv=hit+offsets[i]*radius;
        if(any(lessThan(uv,vec2(0.001))) || any(greaterThan(uv,vec2(0.999)))) continue;
        bool valid;
        float z=traceSurfaceDepth(depthtex1,uv,valid);
        // Roughness integrates sky coverage around foliage; rejecting those taps
        // preserves hard black/sky speckles instead of filtering the silhouette.
        if(!valid || (centerValid && abs(z-centerZ)<max(0.15,abs(centerZ)*0.02)
            && waterReflectionAboveSurface(uv,isEyeInWater==1))) {
            sum+=textureScreen(colortex6,uv).rgb*0.15;
            weight+=0.15;
        }
    }
    return sum/weight;
}

void main(){
    // Evaluate derivatives before alpha/material branches and discarded lanes.
    vec2 waveDx=dFdx(worldPos.xz),waveDy=dFdy(worldPos.xz);
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
    materialData=vec4(WATER_ROUGHNESS,lmcoord.y,0.0,0.25);
    vec4 tex=texture(gtexture,texcoord)*glcolor;
    if(tex.a<0.001) discard;
    if(abs(materialId-1008.0)<0.5){
        color=vec4(lavaRadiance(tex.rgb),1.0);
        materialData=vec4(0.85,lmcoord.y,1.0,0.0);
        return;
    }
    if(abs(materialId-1003.0)>0.5){
        vec3 albedo=srgbToLinear(tex.rgb);
        color=vec4(shadeSurface(albedo,normalize(viewNormal),viewPos,lmcoord,0.24,0.0,0.0,vec3(0.04)),tex.a); return;
    }
    vec2 screenUV=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
    // Optical surface and opaque depth now share the same projection and camera frame.
    vec3 surfacePos=waterFragmentPosition();
    float waveCrest;
    vec2 slope=waterSlope(worldPos.xz,waveDx,waveDy,waveCrest);
    bool underwater=isEyeInWater==1;
    vec3 N=waterNormal(slope),V=normalize(-surfacePos);
    vec3 meshN=normalize(mat3(gbufferModelView)*waterSurfaceNormal(worldDirection(normalize(viewNormal)),vec2(0.0)));
    if(dot(meshN,V)<0.0) meshN=-meshN;
    // Both the wave normal and reflected ray retain their physical direction.
    bool validBehind;
    vec3 behind=opaquePosition(screenUV,validBehind);
    float bottomDepth=validBehind?max(worldUpDelta(surfacePos-behind),0.0):80.0;
    vec3 R=reflect(-V,N);
    // Unresolved capillary waves broaden highlights rather than vanish into a mirror.
    float footprint=max(length(waveDx),length(waveDy));
    float roughness=filteredRoughness(N,sqrt(WATER_ROUGHNESS*WATER_ROUGHNESS
        +0.012*smoothstep(0.15,2.0,footprint)));
    float reflectionSpread=waterReflectionSpread(R,roughness);
    float thickness=validBehind?clamp(length(behind-surfacePos),0.0,80.0):80.0;
    vec2 refractUV=screenUV;
    float refractWeight=0.0;
    #ifdef WATER_REFRACTION
    vec3 incident=normalize(surfacePos);
    vec3 refracted=refract(incident,N,isEyeInWater==1?1.333:0.7502);
    float opticalTravel=min(thickness,2.8);
    vec3 flatRefracted=refract(incident,meshN,underwater?1.333:0.7502);
    vec4 projected=gbufferProjection*vec4(surfacePos+refracted*opticalTravel,1.0);
    vec4 flatProjected=gbufferProjection*vec4(surfacePos+flatRefracted*opticalTravel,1.0);
    vec2 distortion=(projected.xy/max(projected.w,0.001)
                    -flatProjected.xy/max(flatProjected.w,0.001))*0.5;
    // Smoothly bound distortion in screen-height units, including near-camera water.
    vec2 aspect=vec2(viewWidth/viewHeight,1.0);
    float distortionLength=length(distortion*aspect);
    distortion/=sqrt(1.0+distortionLength*distortionLength/(0.012*0.012));
    vec2 candidate=screenUV+distortion;
    if(projected.w>0.0 && flatProjected.w>0.0 && dot(flatRefracted,flatRefracted)>0.001 && all(greaterThan(candidate,vec2(0.001))) && all(lessThan(candidate,vec2(0.999)))) {
        bool validRefracted;
        vec3 refractPos=opaquePosition(candidate,validRefracted);
        vec3 candidateRay=normalize(viewPosition(candidate,0.5));
        float planeDenom=dot(meshN,candidateRay);
        float planeDistance=dot(meshN,surfacePos)/(planeDenom<0.0?min(planeDenom,-0.0001):max(planeDenom,0.0001));
        bool behindPlane=validRefracted && dot(refractPos,candidateRay)>planeDistance+0.02;
        bool submerged=!validRefracted || worldUpDelta(surfacePos-refractPos)>0.01;
        if((!validRefracted || behindPlane) && (underwater || submerged)) {
            refractUV=candidate;
            float clearance=validRefracted?dot(refractPos,candidateRay)-planeDistance:1.0;
            float waterDepth=validRefracted?worldUpDelta(surfacePos-refractPos):1.0;
            refractWeight=edgeFade(candidate)*smoothstep(0.02,0.30,clearance)
                *(underwater?1.0:smoothstep(0.01,0.30,waterDepth))
                *smoothstep(0.0,0.50,thickness);
        }
    }
    #endif
    // Water dispersion is tiny; one validated lookup avoids colored foreground leaks.
    vec3 transmitted=mix(textureScreen(colortex6,screenUV).rgb,
        textureScreen(colortex6,refractUV).rgb,refractWeight);

    // Wavelength-dependent absorption through the water column.
    // Above-surface terrain/sky is reached through air. Eye-to-surface water
    // absorption is applied once by composite, not again using the air distance.
    vec3 absorption = underwater?vec3(0.0):waterAbsorption();
    vec3 transmittance = exp(-absorption * thickness);

    // Murky natural freshwater: earthy moss/olive shallows transitioning to deep sediment-peat
    float day = daylight();
    vec3 waterColor = waterBodyColor(thickness,lmcoord.y);

    transmitted = transmitted * transmittance + waterColor * (1.0 - transmittance);

    // Forward Subsurface Scattering (In-Scatter: sunlight penetrating translucent wave crests)
    #if !defined(NETHER) && !defined(END)
    vec3 L = normalize(shadowLightPosition);
    float sunScatterLobe = pow(sat(dot(V, -L)), 4.0) * 0.70 + pow(sat(dot(V, -L) * 0.5 + 0.5), 2.0) * 0.30;
    vec3 sssColor = vec3(0.045, 0.082, 0.038);
    float sssCrest = 0.50 + 0.80 * sat(waveCrest);
    vec3 waveSSS = sssColor * lightColor() * sunScatterLobe * (1.0 - transmittance.g) * min(thickness, 4.0) * 0.16 * lmcoord.y * sssCrest;
    if(!underwater) transmitted += waveSSS;

    // Gentle natural foam in shallow shoreline wash (continuous multi-frequency noise)
    if(!underwater && validBehind && bottomDepth < 0.38) {
        float foamNoise = sin(worldPos.x * 5.2 + sin(worldPos.z * 4.1)) * cos(worldPos.z * 5.2 + sin(worldPos.x * 4.1)) * 0.5 + 0.5;
        float foamEdge = 1.0-smoothstep(0.03, 0.35, bottomDepth);
        float foamWave = smoothstep(0.20, 0.65, waveCrest + foamEdge * 0.35);
        float foam = foamEdge * foamWave * (0.65 + 0.35 * foamNoise);
        vec3 foamCol = vec3(0.92, 0.93, 0.88) * (lightColor() * 0.85 + 0.15) * lmcoord.y;
        transmitted = mix(transmitted, foamCol, foam * 0.68);
    }
    #endif

    #ifdef WATER_CAUSTICS
    // Focused organic cellular caustics on submerged surfaces
    vec2 cPos = ((gbufferModelViewInverse*vec4(behind,1.0)).xyz+cameraPosition).xz;
    float causticFootprint=max(length(dFdx(cPos)),length(dFdy(cPos)))*3.6;
    float causticFilter=1.0-smoothstep(0.7,2.8,causticFootprint);
    if(validBehind && !underwater && causticFilter>0.0 && day>0.0 && lmcoord.y>0.0) {
        float causticWave=waterCaustic(cPos,mod(frameTimeCounter,6283.1853)*(0.65*WIND_SPEED));
        vec3 caustColor=vec3(0.080,0.095,0.045)*causticWave*causticFilter*exp(-thickness*0.45)*day*lmcoord.y;
        transmitted+=caustColor*transmittance;
    }
    #endif

    // Underside light must be spatially continuous, not a fluid-quad lightmap grid.
    float skyExposure=underwater?smoothstep(8.0,180.0,float(eyeBrightnessSmooth.y)):lmcoord.y;
    vec3 worldRay=worldDirection(R);
    float fresnel=waterFresnel(dot(N,V),underwater)*waterFacetVisibility(dot(N,V),roughness,underwater);
    vec3 reflected=vec3(0.0);
    // One primary screen ray with a filtered environment cone on misses.
    if(fresnel>0.0) {
    #ifdef SSR
        vec3 envRadiance=waterEnvironmentReflection(worldRay,reflectionSpread)*skyExposure*skyExposure;
        vec3 ray=normalize(mat3(gbufferModelView)*worldRay);
        reflected=envRadiance;
        float visibleRay=underwater?1.0:smoothstep(0.0,0.08,dot(ray,meshN));
        vec2 hit;
        float confidence;
        float screenCoverage=0.0;
        vec3 screenReflection=vec3(0.0);
        if(visibleRay>0.001 && traceScreen(depthtex1,surfacePos+meshN*0.04,ray,0.22,SSR_STEPS,hit,confidence)) {
            bool hitValid;
            vec3 hitPosition=opaquePosition(hit,hitValid);
            float surfaceHeight=worldUpDelta(hitPosition-surfacePos);
            float surfaceFade=underwater?1.0:smoothstep(-0.02,0.25,surfaceHeight);
            if(underwater || (hitValid && surfaceHeight>=-0.02)) {
                float coverage=edgeFade(hit)*confidence*surfaceFade*visibleRay;
                if(coverage>0.0) {
                    screenCoverage=coverage;
                    screenReflection=waterReflectionSample(hit,roughness);
                }
            }
        }
        #if defined(AA_VOXELS) || defined(AA_LIGHT_SPACE)
        // Above-water only; omit submerged surfaces and fully covered screen rays.
        if(!underwater && visibleRay>0.001 && screenCoverage<0.5) {
            vec3 secondary; float secondaryConfidence;
            if(traceSceneFallback(surfacePos+meshN*0.04,ray,24,secondary,secondaryConfidence))
                reflected=mix(reflected,secondary,secondaryConfidence*visibleRay*(1.0-smoothstep(0.15,0.5,screenCoverage)));
        }
        #endif
        reflected=mix(reflected,screenReflection,screenCoverage);
    #else
    if(skyExposure>0.0) reflected=waterEnvironmentReflection(worldRay,reflectionSpread)*skyExposure*skyExposure;
    #endif
    }

    // Ocean Sun & Moon Glitter: physically based specular with anisotropic diamond glints
    vec3 glint = vec3(0.0);
    #if !defined(NETHER) && !defined(END)
    float nl = dot(N, L);
    if(nl > 0.001 && lmcoord.y > 0.05){
        float vis = shadowVisibility(worldPos - cameraPosition, worldDirection(N), nl, true);
        if(vis > 0.001){
            vec3 specular = specularBRDF(N, V, L, roughness, vec3(0.0204)) * lightColor() * vis * lmcoord.y * cloudShadow(worldPos);

            glint = specular;
        }
    }
    #endif

    vec3 result = mix(transmitted, reflected, fresnel) + glint;


    color = vec4(max(result, vec3(0.0)), 1.0);
}
