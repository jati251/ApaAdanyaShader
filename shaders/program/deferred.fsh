#include "/lib/common.glsl"
#include "/lib/environment.glsl"
#include "/lib/trace.glsl"
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif
uniform sampler2D colortex0,colortex1,colortex2,depthtex0;
in vec2 texcoord;
/* RENDERTARGETS: 0,6 */
layout(location=0) out vec4 color;
layout(location=1) out vec4 opaqueCopy;
/* const int colortex0Format = RGBA16F; */
/* const int colortex1Format = RGBA16F; */
/* const int colortex2Format = RGBA8; */
/* const int colortex6Format = RGBA16F; */
const vec4 colortex1ClearColor=vec4(0.5,0.5,1.0,0.0);
const vec4 colortex2ClearColor=vec4(1.0,0.0,0.0,0.0);
void main(){
    float depth=texture(depthtex0,texcoord).r;
    vec3 vp=viewPosition(texcoord,depth);
    vec3 rd=worldDirection(normalize(vp));
    vec3 scene=texture(colortex0,texcoord).rgb;
    bool isDH=false;
    #ifdef DISTANT_HORIZONS
    float dhDepth=texture(dhDepthTex0,texcoord).r;
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
        #if defined(VOLUMETRIC_CLOUDS) && !defined(NETHER) && !defined(END)
        scene = renderClouds(rd, sky, gl_FragCoord.xy);
        #else
        scene = sky;
        #endif
    }
    else if(!isDH) {
        vec4 mat=texture(colortex2,texcoord);
        vec3 N=normalize(texture(colortex1,texcoord).xyz*2.0-1.0);
        if(mat.a<0.5) {
            float distToCam=length(vp);
            if(distToCam<48.0) {
                float occ=0.0; float rotation=hash12(gl_FragCoord.xy)*6.283;
                vec2 projScale=vec2(gbufferProjection[0][0],gbufferProjection[1][1])/max(-vp.z,1.0)*0.5;
                for(int i=0;i<8;i++) {
                    float angle=float(i)*2.39996+rotation;
                    float radius=1.5*sqrt((float(i)+0.5)/8.0);
                    vec2 uv=texcoord+vec2(cos(angle),sin(angle))*(radius*projScale);
                    if(any(lessThan(uv,vec2(0)))||any(greaterThan(uv,vec2(1)))) continue;
                    float d=texture(depthtex0,uv).r;
                    vec3 diff=viewPosition(uv,d)-vp;
                    float len=length(diff);
                    occ+=max(dot(N,diff/max(len,0.001))-0.10,0.0)*(1.0-smoothstep(0.1,2.4,len))*step(d,0.99999);
                }
                float aoFade=1.0-smoothstep(32.0,48.0,distToCam);
                scene*=1.0-occ*0.105*(1.0-mat.b)*aoFade;
            }
            #ifdef SSGI
            if(distToCam<42.0) {
                float distWeight=1.0-smoothstep(24.0,42.0,distToCam);
                vec3 tangent=normalize(cross(N,abs(N.y)<0.9?vec3(0,1,0):vec3(1,0,0)));
                vec3 bitangent=cross(N,tangent); vec3 bounce=vec3(0);
                for(int i=0;i<GI_SAMPLES;i++) {
                    float angle=rotation+float(i)*2.39996;
                    float z=sqrt((float(i)+0.5)/float(GI_SAMPLES));
                    float r=sqrt(1.0-z*z);
                    vec3 dir=normalize(tangent*cos(angle)*r+bitangent*sin(angle)*r+N*z);
                    vec2 hit;
                    if(traceScreen(depthtex0,vp+N*0.08,dir,0.18,10,hit)) {
                        vec3 incoming=texture(colortex0,hit).rgb;
                        vec3 hitN=normalize(texture(colortex1,hit).xyz*2.0-1.0);
                        bounce+=min(incoming,vec3(3))*max(dot(hitN,-dir),0.0)*edgeFade(hit);
                    }
                }
                scene+=bounce/float(GI_SAMPLES)*GI_STRENGTH*sqrt(max(scene,vec3(0.015)))*distWeight;
            }
            #endif
            #ifdef SSR
            if(mat.r<0.38) {
                vec3 reflected=reflect(normalize(vp),N); vec2 hit;
                vec3 reflection=environmentRadiance(worldDirection(reflected))*mat.g*mat.g;
                if(traceScreen(depthtex0,vp+N*0.08,reflected,0.30,min(SSR_STEPS,48),hit)) reflection=mix(reflection,texture(colortex0,hit).rgb,edgeFade(hit));
                float fresnel=0.04+0.96*pow(1.0-max(dot(N,normalize(-vp)),0.0),5.0);
                scene=mix(scene,reflection,fresnel*(1.0-mat.r));
            }
            #endif
        }
    }
    color=vec4(max(scene,vec3(0)),1); opaqueCopy=color;
}



