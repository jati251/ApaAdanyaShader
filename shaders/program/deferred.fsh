#include "/lib/common.glsl"
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
in vec2 texcoord;
/* RENDERTARGETS: 0,6 */
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
    float depth=depthScreen(depthtex0,texcoord);
    vec3 scene=textureScreen(colortex0,texcoord).rgb;
    bool isDH=false;
    #ifdef DISTANT_HORIZONS
    // The opaque-copy DH depth is refreshed only before DH translucency,
    // AFTER deferred. It can still contain last frame's camera silhouette here.
    float dhDepth=depthScreen(dhDepthTex0,texcoord);
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
            #ifdef SHADOWS
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
                vec3 reflected=reflect(V_dir,N); vec2 hit; float confidence;
                vec3 wr=worldDirection(reflected);
                bool roughDielectric=mat.r>=0.60 && max(f0.r,max(f0.g,f0.b))<0.12;
                // Matte stone/grass/wood need a broad sky lobe, not five cache directions.
                vec3 reflection=environmentRadiance(roughDielectric?worldDirection(N):wr);
                // Small angular convolution of the sky cache for rough materials.
                // This is a bounded approximation, not a prefiltered cubemap/voxel trace.
                if(mat.r>0.18 && !roughDielectric) {
                    vec3 t=normalize(cross(wr,abs(wr.y)<0.9?vec3(0,1,0):vec3(1,0,0)));
                    vec3 b=cross(wr,t);
                    float spread=mat.r*mat.r*1.5;
                    reflection=(reflection*2.0+environmentRadiance(normalize(wr+t*spread))
                        +environmentRadiance(normalize(wr-t*spread))+environmentRadiance(normalize(wr+b*spread))
                        +environmentRadiance(normalize(wr-b*spread)))/6.0;
                }
                reflection*=mat.g*mat.g;
                // Skip rays whose sharp reflected signal cannot represent this rough lobe.
                if(mat.r<0.60 && traceScreen(depthtex0,vp+N*0.08,reflected,0.30,SSR_STEPS,hit,confidence))
                    reflection=mix(reflection,textureScreen(colortex0,hit).rgb,edgeFade(hit)*confidence*(1.0-smoothstep(0.18,0.60,mat.r)));
                float nv=sat(dot(N,-V_dir));
                #if defined(SSAO) || defined(SSGI)
                // Physically-based specular occlusion (Lagarde): suppresses sky reflections in occluded crevices
                float specOcc = sat(nv + indirect.a - 1.0 + indirect.a);
                reflection *= mix(specOcc, 1.0, 1.0 - response.a);
                #endif
                float fnv=1.0-nv; float fnv2=fnv*fnv;
                vec3 fresnel=f0+(max(vec3(1.0-mat.r),f0)-f0)*(fnv2*fnv2*fnv);
                // Add the environment specular lobe; mixing the entire scene erased direct light.
                scene+=reflection*fresnel/(1.0+mat.r*mat.r);
            }
            #endif
        }
    }
    #endif
    color=vec4(max(scene,vec3(0.0)),1.0); opaqueCopy=color;
}
