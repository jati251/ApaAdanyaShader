#include "/lib/common.glsl"
#include "/lib/lighting.glsl"
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

vec3 waterNormal(vec2 slope){
    vec3 base=worldDirection(normalize(viewNormal));
    vec3 nw=waterSurfaceNormal(base,slope);
    return normalize(mat3(gbufferModelView)*nw)*(gl_FrontFacing?1.0:-1.0);
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
    return viewPos+normalize(viewPos)*80.0;
}

float worldUpDelta(vec3 v) {
    return dot(vec3(gbufferModelViewInverse[0][1], gbufferModelViewInverse[1][1], gbufferModelViewInverse[2][1]), v);
}

bool waterReflectionAboveSurface(vec2 hit,bool underwater) {
    if(underwater) return true;
    bool valid;
    vec3 position=opaquePosition(hit,valid);
    // Ocean reflection cannot originate from a submerged bed or underwater plant.
    return valid && worldUpDelta(position-viewPos)>=-0.02;
}

vec3 waterReflectionSample(vec2 hit,float roughness) {
    vec3 center=textureScreen(colortex6,hit).rgb;
    if(roughness<=0.08) return center;
    bool centerValid;
    float centerZ=traceSurfaceDepth(depthtex1,hit,centerValid);
    vec2 radius=max(vec2(roughness*0.004),1.5/vec2(viewWidth,viewHeight));
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
    float waveCrest;
    vec2 slope=waterSlope(worldPos.xz,waveDx,waveDy,waveCrest);
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
    materialData=vec4(WATER_ROUGHNESS,lmcoord.y,0.0,0.25);
    vec4 tex=texture(gtexture,texcoord)*glcolor;
    if(tex.a<0.001) discard;
    if(abs(materialId-1003.0)>0.5){
        vec3 albedo=srgbToLinear(tex.rgb);
        color=vec4(shadeSurface(albedo,normalize(viewNormal),viewPos,lmcoord,0.24,0.0,0.0,vec3(0.04)),tex.a); return;
    }
    vec2 screenUV=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
    bool underwater=isEyeInWater==1;
    vec3 N=waterNormal(slope),V=normalize(-viewPos);
    vec3 meshN=normalize(mat3(gbufferModelView)*waterSurfaceNormal(worldDirection(normalize(viewNormal)),vec2(0.0)));
    if(dot(meshN,V)<0.0) meshN=-meshN;
    // Both the wave normal and reflected ray retain their physical direction.
    bool validBehind;
    vec3 behind=opaquePosition(screenUV,validBehind);
    float bottomDepth=validBehind?max(worldUpDelta(viewPos-behind),0.0):80.0;
    vec3 R=reflect(-V,N);
    // Unresolved capillary waves broaden highlights rather than vanish into a mirror.
    float footprint=max(length(waveDx),length(waveDy));
    float roughness=filteredRoughness(N,sqrt(WATER_ROUGHNESS*WATER_ROUGHNESS
        +0.012*smoothstep(0.15,2.0,footprint)));
    float reflectionSpread=waterReflectionSpread(R,roughness);
    float thickness=validBehind?clamp(length(behind-viewPos),0.0,80.0):80.0;
    vec2 refractUV=screenUV;
    float refractWeight=0.0;
    #ifdef WATER_REFRACTION
    vec3 incident=normalize(viewPos);
    vec3 refracted=refract(incident,N,isEyeInWater==1?1.333:0.7502);
    vec3 target=viewPos+refracted*min(thickness,2.8);
    vec4 projected=gbufferProjection*vec4(target,1.0);
    vec2 candidate=projected.xy/max(projected.w,0.001)*0.5+0.5;
    if(projected.w>0.0 && all(greaterThan(candidate,vec2(0.001))) && all(lessThan(candidate,vec2(0.999)))) {
        bool validRefracted;
        vec3 refractPos=opaquePosition(candidate,validRefracted);
        vec3 candidateRay=normalize(viewPosition(candidate,0.5));
        float planeDenom=dot(meshN,candidateRay);
        float planeDistance=dot(meshN,viewPos)/min(planeDenom,-0.0001);
        bool behindPlane=validRefracted && dot(refractPos,candidateRay)>planeDistance+0.02;
        bool submerged=!validRefracted || worldUpDelta(viewPos-refractPos)>0.01;
        if((!validRefracted || behindPlane) && (underwater || submerged)) {
            refractUV=candidate;
            float clearance=validRefracted?dot(refractPos,candidateRay)-planeDistance:1.0;
            float waterDepth=validRefracted?worldUpDelta(viewPos-refractPos):1.0;
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
    float causticWave = waterCaustic(cPos, mod(frameTimeCounter, 6283.1853) * (0.65 * WIND_SPEED));
    float causticFootprint=max(length(dFdx(cPos)),length(dFdy(cPos)))*3.6;
    float causticFilter=1.0-smoothstep(0.7,2.8,causticFootprint);
    vec3 caustColor = vec3(0.080, 0.095, 0.045) * causticWave * causticFilter * exp(-thickness * 0.45) * day * lmcoord.y;
    if(validBehind && !underwater) transmitted += caustColor * transmittance;
    #endif

    // Underside light must be spatially continuous, not a fluid-quad lightmap grid.
    float skyExposure=underwater?smoothstep(8.0,180.0,float(eyeBrightnessSmooth.y)):lmcoord.y;
    vec3 worldRay=worldDirection(R);
    vec3 reflected=waterEnvironmentReflection(worldRay,reflectionSpread)*skyExposure*skyExposure;
    #ifdef SSR
    vec3 reflectionSum=vec3(0);
    // Integrate a fixed ray cone. A missed trace retains its environment tap,
    // instead of replacing the entire reflection with a new hit in one frame.
    for(int tap=0;tap<7;tap++) {
        vec3 worldSample=waterReflectionRay(worldRay,reflectionSpread,tap);
        vec3 ray=normalize(mat3(gbufferModelView)*worldSample);
        vec3 radiance=environmentRadiance(worldSample)*skyExposure*skyExposure;
        float visibleRay=underwater?1.0:smoothstep(0.0,0.08,dot(ray,meshN));
        vec2 hit;
        float confidence;
        if(visibleRay>0.001 && traceScreen(depthtex1,viewPos+meshN*0.04,ray,0.22,SSR_STEPS,hit,confidence)
            && waterReflectionAboveSurface(hit,underwater)) {
            bool hitValid;
            vec3 hitPosition=opaquePosition(hit,hitValid);
            float surfaceFade=underwater?1.0:smoothstep(-0.02,0.25,worldUpDelta(hitPosition-viewPos));
            float coverage=edgeFade(hit)*confidence*surfaceFade*visibleRay;
            radiance=mix(radiance,waterReflectionSample(hit,roughness),coverage);
        }
        reflectionSum+=radiance*waterReflectionTapWeight(tap);
    }
    reflected=reflectionSum;
    #endif

    float fresnel=waterFresnel(dot(N,V),underwater)*waterFacetVisibility(dot(N,V),roughness,underwater);

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
