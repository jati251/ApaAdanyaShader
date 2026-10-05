#include "/lib/common.glsl"
#include "/lib/environment.glsl"
#include "/lib/trace.glsl"
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjectionInverse;
#endif
uniform sampler2D colortex0,colortex1,colortex2,depthtex0;
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
*/
const vec4 colortex1ClearColor=vec4(0.5,0.5,1.0,0.0);
const vec4 colortex2ClearColor=vec4(1.0,0.0,0.0,0.0);
void main(){
    float depth=texture(depthtex0,texcoord).r;
    vec3 vp=viewPosition(texcoord,depth);
    vec3 rd=worldDirection(normalize(vp));
    vec3 scene=texture(colortex0,texcoord).rgb;
    bool isDH=false;
    #ifdef DISTANT_HORIZONS
    float dhSolidD=texture(dhDepthTex0,texcoord).r;
    float dhTransD=texture(dhDepthTex1,texcoord).r;
    float dhDepth=min(dhSolidD,dhTransD);
    if(depth>=0.999999 && dhDepth<1.0){
        isDH=true;
        vec4 clipDH=vec4(texcoord*2.0-1.0,dhDepth*2.0-1.0,1.0);
        vec4 vpDH=dhProjectionInverse*clipDH;
        vp=vpDH.xyz/vpDH.w;
        rd=worldDirection(normalize(vp));
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
        vec4 mat=texture(colortex2,texcoord);
        vec3 N=normalize(texture(colortex1,texcoord).xyz*2.0-1.0);
        if(mat.a<0.5) {
            #if defined(SSAO) || defined(SSGI)
            vec4 indirect;
            #ifdef HALF_RES_LIGHTING
            indirect=reconstructIndirect(texcoord,vp,N,mat);
            #else
            indirect=sampleIndirect(texcoord,vp,N,mat,gl_FragCoord.xy);
            #endif
            scene*=indirect.a;
            scene+=indirect.rgb*sqrt(max(scene,vec3(0.015)));
            #endif
            #ifdef SSR
            if(mat.r<0.38) {
                vec3 reflected=reflect(normalize(vp),N); vec2 hit;
                vec3 reflection=environmentRadiance(worldDirection(reflected))*mat.g*mat.g;
                if(traceScreen(depthtex0,vp+N*0.08,reflected,0.30,SSR_STEPS,hit)) reflection=mix(reflection,texture(colortex0,hit).rgb,edgeFade(hit));
                vec3 f0=vec3(0.04);
                #ifdef RESOURCE_SPECULAR
                f0=texture(colortex3,texcoord).rgb;
                #endif
                vec3 fresnel=f0+(1.0-f0)*pow(1.0-max(dot(N,normalize(-vp)),0.0),5.0);
                scene=mix(scene,reflection,fresnel*(1.0-mat.r));
            }
            #endif
        }
    }
    #endif
    color=vec4(max(scene,vec3(0.0)),1.0); opaqueCopy=color;
}

