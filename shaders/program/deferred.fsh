#include "/lib/common.glsl"
#ifdef AA_VOXELS
const float voxelDistance=56.0;
#endif
#include "/lib/environment.glsl"
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#define AA_TRACE_DH
#define AA_TRACE_DH_DEPTH dhDepthTex0
#endif
#include "/lib/trace.glsl"
uniform sampler2D colortex0,colortex1,colortex2,colortex15,depthtex0;
#include "/lib/material.glsl"
#ifdef RESOURCE_SPECULAR
uniform sampler2D colortex3;
/*
const int colortex3Format=RGBA8;
*/
const vec4 colortex3ClearColor=vec4(0.04,0.04,0.04,0.0);
#endif
#include "/lib/indirect.glsl"
#include "/lib/reconstruct_indirect.glsl"
#include "/lib/reconstruct_clouds.glsl"
#include "/lib/rough_reflection.glsl"
in vec2 texcoord;
#ifdef AA_VNDF_REFLECTION
/* RENDERTARGETS: 0,6,20 */
layout(location=2) out vec4 reflectionHistory;
/*
const int colortex20Format=RGBA16F;
const bool colortex20Clear=false;
*/
#else
/* RENDERTARGETS: 0,6 */
#endif
layout(location=0) out vec4 color;
layout(location=1) out vec4 opaqueCopy;
/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
const int colortex2Format = RGBA8;
const int colortex6Format = RGBA16F;
const int colortex15Format = RGBA8;
*/
const vec4 colortex15ClearColor=vec4(0.0,0.0,0.0,0.0);
const vec4 colortex1ClearColor=vec4(0.5,0.5,1.0,0.0);
const vec4 colortex2ClearColor=vec4(1.0,0.0,0.0,0.0);
void main(){
    #ifdef AA_VNDF_REFLECTION
    reflectionHistory=vec4(0);
    #endif
    float depth=depthScreen(depthtex0,texcoord);
    vec3 scene=textureScreen(colortex0,texcoord).rgb;
    bool isDH=false;
    #ifdef DISTANT_HORIZONS
    // The opaque-copy DH depth is refreshed only before DH translucency,
    // AFTER deferred. It can still contain last frame's camera silhouette here.
    float dhDepth=1.0;
    if(depth>=0.999999) dhDepth=depthScreen(dhDepthTex0,texcoord);
    if(depth>=0.999999 && dhDepth<1.0){
        isDH=true;
    }
    #endif
    // Low tiers only reconstruct sky rays; opaque vanilla/DH already has lighting.
    vec3 vp=vec3(0.0),V_dir=vec3(0.0),rd=vec3(0.0);
    #if defined(SSAO) || defined(SSGI) || defined(SSR)
    bool needsView=true;
    #else
    bool needsView=depth>=0.999999 && !isDH;
    #endif
    if(needsView){
        vp=viewPosition(texcoord,depth);
        V_dir=normalize(vp);
        rd=worldDirection(V_dir);
    }
    #if defined(DISTANT_HORIZONS) && (defined(SSAO) || defined(SSGI) || defined(SSR))
    if(isDH){
        vec4 clipDH=vec4(texcoord*2.0-1.0,dhDepth*2.0-1.0,1.0);
        vec4 vpDH=dhProjectionInverse*clipDH;
        vp=vpDH.xyz/vpDH.w;
        V_dir=normalize(vp);
        rd=worldDirection(V_dir);
    }
    #endif
    if(depth>=0.999999 && !isDH) {
        vec3 sky = skyRadiance(rd);
        #if CLOUDS == 2 && !defined(NETHER) && !defined(END)
        #ifdef CLOUD_RECONSTRUCTION
        vec4 layer=reconstructClouds(texcoord,rd);
        scene=sky*(1.0-layer.a)+layer.rgb;
        #else
        scene = renderClouds(rd, sky, gl_FragCoord.xy);
        #endif
        #elif CLOUDS == 1 && !defined(NETHER) && !defined(END)
        scene = renderFastClouds(rd, sky);
        #else
        scene = sky;
        #endif
    }
    #if defined(SSAO) || defined(SSGI) || defined(SSR)
    else if(!isDH) {
        vec4 mat=textureScreen(colortex2,texcoord);
        vec3 N=normalize(textureScreen(colortex1,texcoord).xyz*2.0-1.0);
        if(mat.a<0.5) {
            #if defined(SSAO) || defined(SSGI)
            vec4 indirect;
            #ifdef HALF_RES_LIGHTING
            indirect=reconstructIndirect(texcoord,vp,N,mat);
            #else
            indirect=sampleIndirect(texcoord,vp,N,mat,gl_FragCoord.xy);
            #endif
            vec4 response=textureScreen(colortex15,texcoord);
            scene*=mix(1.0,indirect.a,response.a);
            scene+=indirect.rgb*response.rgb;
            #if !defined(NETHER) && !defined(END)
            #if defined(SHADOWS) && !defined(AA_VOXELS)
            // Screen-Space Ray-Traced Contact Shadows (RT Shadows)
            // Pixel-perfect contact occlusion for small geometry, grass, and crevices
            vec3 lightDirV=normalize(shadowLightPosition);
            float ndl=dot(N,lightDirV);
            if(ndl>0.01 && response.a<0.88 && vp.z>-36.0) {
                ivec2 depthSize=screenTextureSize(depthtex0);
                float rtShadow=traceScreenShadow(depthtex0,depthSize,vp+N*0.05,lightDirV,2.5,10);
                if(rtShadow>0.001) {
                    float directFraction=1.0-response.a;
                    scene*=(1.0-directFraction*rtShadow*0.80);
                }
            }
            #endif
            #endif
            #endif
            #ifdef SSR
            if(mat.b<0.99) {
                vec3 f0=vec3(0.04);
                #ifdef RESOURCE_SPECULAR
                f0=textureScreen(colortex3,texcoord).rgb;
                #endif
                vec3 reflected=reflect(V_dir,N); vec2 hit=vec2(0.0); float confidence=0.0;
                #ifdef AA_VNDF_REFLECTION
                vec3 halfNormal=N;
                bool stochastic=mat.r<0.75;
                if(stochastic) {
                    vec2 randomValue=vec2(ignDither(gl_FragCoord.xy),hash12(gl_FragCoord.xy+vec2(19.31,5.71)));
                    randomValue=fract(randomValue+float(frameCounter%64)*vec2(0.75487766,0.56984029));
                    reflected=sampleVisibleGGX(N,-V_dir,mat.r,randomValue,halfNormal);
                }
                float traceRoughness=stochastic?0.0:mat.r;
                #else
                float traceRoughness=mat.r;
                #endif
                vec3 wr=worldDirection(reflected);
                bool roughDielectric=traceRoughness>=0.60 && max(f0.r,max(f0.g,f0.b))<0.12;
                // Matte stone/grass/wood need a broad sky lobe, not five cache directions.
                vec3 reflection=environmentRadiance(roughDielectric?worldDirection(N):wr);
                // Small angular convolution of the sky cache for rough materials.
                // This is a bounded approximation, not a prefiltered cubemap/voxel trace.
                if(traceRoughness>0.18 && !roughDielectric) {
                    vec3 t=normalize(cross(wr,abs(wr.y)<0.9?vec3(0,1,0):vec3(1,0,0)));
                    vec3 b=cross(wr,t);
                    float spread=mat.r*mat.r*1.5;
                    reflection=(reflection*2.0+environmentRadiance(normalize(wr+t*spread))
                        +environmentRadiance(normalize(wr-t*spread))+environmentRadiance(normalize(wr+b*spread))
                        +environmentRadiance(normalize(wr-b*spread)))/6.0;
                }
                reflection*=mat.g*mat.g;
                float screenCoverage=0.0;
                vec3 screenReflection=vec3(0.0);
                if(traceRoughness<0.60 && dot(N,reflected)>0.0 && traceScreen(depthtex0,vp+N*0.08,reflected,0.30,SSR_STEPS,hit,confidence)) {
                    screenCoverage=edgeFade(hit)*confidence*(1.0-smoothstep(0.18,0.60,traceRoughness));
                    screenReflection=textureScreen(colortex0,hit).rgb;
                }
                #if defined(AA_VOXELS) || defined(AA_LIGHT_SPACE)
                if(traceRoughness<0.60 && dot(N,reflected)>0.0 && screenCoverage<0.5) {
                    vec3 secondary; float secondaryConfidence;
                    if(traceSceneFallback(vp+N*0.08,reflected,24,secondary,secondaryConfidence))
                        reflection=mix(reflection,secondary,secondaryConfidence*(1.0-smoothstep(0.18,0.60,traceRoughness))*(1.0-smoothstep(0.15,0.5,screenCoverage)));
                }
                #endif
                // Skip rays whose sharp reflected signal cannot represent this rough lobe.
                reflection=mix(reflection,screenReflection,screenCoverage);
                float nv=sat(dot(N,-V_dir));
                #if defined(SSAO) || defined(SSGI)
                // Physically-based specular occlusion (Lagarde): suppresses sky reflections in occluded crevices
                float specOcc = sat(nv + indirect.a - 1.0 + indirect.a);
                reflection *= mix(specOcc, 1.0, 1.0 - response.a);
                #endif
                float fnv=1.0-nv; float fnv2=fnv*fnv;
                vec3 fresnel=f0+(max(vec3(1.0-mat.r),f0)-f0)*(fnv2*fnv2*fnv);
                // Add the environment specular lobe; mixing the entire scene erased direct light.
                vec3 reflectionLobe=reflection*fresnel/(1.0+mat.r*mat.r);
                #ifdef AA_VNDF_REFLECTION
                if(stochastic) reflectionLobe=reflection*visibleGGXWeight(N,-V_dir,reflected,halfNormal,mat.r,f0);
                reflectionLobe=stabilizeReflection(texcoord,vp,mat,reflectionLobe);
                float sourceSign=dot(shadowLightPosition,sunPosition)>=0.0?1.0:-1.0;
                reflectionHistory=vec4(reflectionLobe,min(-vp.z,60000.0)*sourceSign);
                #endif
                scene+=reflectionLobe;
            }
            #endif
        }
    }
    #endif
    color=vec4(max(scene,vec3(0.0)),1.0); opaqueCopy=color;
}
