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

#include "/lib/water.glsl"

vec3 waterNormal(out float waveCrest){
    vec2 slope=waterSlope(worldPos.xz,dFdx(worldPos.xz),dFdy(worldPos.xz),waveCrest);
    vec3 base=worldDirection(normalize(viewNormal));
    // Keep waterfalls and the side faces of a water block aligned with their mesh.
    float horizontal=smoothstep(0.65,0.95,abs(base.y));
    vec3 nw=normalize(base+vec3(-slope.x,0.0,-slope.y)*horizontal);
    return normalize(mat3(gbufferModelView)*nw)*(gl_FrontFacing?1.0:-1.0);
}

vec3 opaquePosition(vec2 uv,out bool valid) {
    float depth=textureScreen(depthtex1,uv).r;
    valid=depth<0.999999;
    if(valid) return viewPosition(uv,depth);
    #ifdef DISTANT_HORIZONS
    float dhD=textureScreen(dhDepthTex0,uv).r;
    if(dhD<1.0){
        valid=true;
        vec4 pos=dhProjectionInverse*vec4(uv*2.0-1.0,dhD*2.0-1.0,1.0);
        return pos.xyz/pos.w;
    }
    #endif
    return viewPos+normalize(viewPos)*80.0;
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
    float roughness=filteredRoughness(N,WATER_ROUGHNESS);
    bool validBehind;
    vec3 behind=opaquePosition(screenUV,validBehind);
    float thickness=validBehind?clamp(length(behind-viewPos),0.0,80.0):80.0;
    vec2 refractUV=screenUV;
    #ifdef WATER_REFRACTION
    vec3 incident=normalize(viewPos);
    vec3 refracted=refract(incident,N,isEyeInWater==1?1.333:0.7502);
    vec3 target=viewPos+refracted*min(thickness,2.8);
    vec4 projected=gbufferProjection*vec4(target,1.0);
    vec2 candidate=projected.xy/max(projected.w,0.001)*0.5+0.5;
    if(projected.w>0.0 && all(greaterThan(candidate,vec2(0.001))) && all(lessThan(candidate,vec2(0.999)))) {
        bool validRefracted;
        vec3 refractPos=opaquePosition(candidate,validRefracted);
        if(!validRefracted || refractPos.z<viewPos.z-0.02) {
            refractUV=candidate;
            behind=refractPos;
            validBehind=validRefracted;
            thickness=validBehind?min(length(behind-viewPos),80.0):80.0;
        }
    }
    #endif
    // Water dispersion is tiny; one validated lookup avoids colored foreground leaks.
    vec3 transmitted=textureScreen(colortex6,refractUV).rgb;

    // Wavelength-dependent absorption through the water column.
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
    vec2 cPos = ((gbufferModelViewInverse*vec4(behind,1.0)).xyz+cameraPosition).xz;
    float ct = frameTimeCounter * 1.6;
    float caustA = sin(cPos.x * 2.2 + cPos.y * 1.6 + ct * 1.4);
    float caustB = cos(cPos.x * 1.8 - cPos.y * 2.3 - ct * 1.2);
    float caustC = sin(cPos.x * 3.6 + cPos.y * 1.1 + ct * 2.1);
    float causticWave = pow(sat(1.0 - abs(caustA + caustB) * 0.5), 5.0) * 0.7 + pow(sat(1.0 - abs(caustB + caustC) * 0.5), 4.0) * 0.3;
    vec3 caustColor = vec3(0.04, 0.14, 0.16) * causticWave * exp(-thickness * 0.28) * day * lmcoord.y;
    if(validBehind) transmitted += caustColor * transmittance;
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

    float fresnel=waterFresnel(dot(N,V),isEyeInWater==1);

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

    #ifdef WATER_FOAM
    float surfaceUp=abs(worldDirection(normalize(viewNormal)).y);
    float waveSurge=sin(worldPos.x*0.45+worldPos.z*0.30+frameTimeCounter*1.8)*0.12;
    float shoreBand=validBehind?1.0-smoothstep(0.01,0.55+waveSurge,thickness):0.0;
    float oceanWhitecap=waterWhitecap(waveCrest,thickness);
    if((shoreBand+oceanWhitecap)>0.001 && surfaceUp>0.65 && isEyeInWater!=1){
        vec2 foamPos=worldPos.xz+vec2(frameTimeCounter*0.20,frameTimeCounter*0.08);
        float froth=noise2D(foamPos*3.8)*0.65+noise2D(foamPos*8.0)*0.35;
        float shoreFoam=smoothstep(0.30,0.68,froth+shoreBand*0.60)*shoreBand;
        float totalFoam=sat(shoreFoam+oceanWhitecap*smoothstep(0.25,0.65,froth));
        vec3 foamColor=vec3(0.88,0.93,0.95)*mix(0.035,1.0,day)*(0.15+lmcoord.y*0.85);
        result=mix(result,foamColor,totalFoam*0.88);
    }
    #endif

    color = vec4(max(result, vec3(0.0)), 1.0);
}



