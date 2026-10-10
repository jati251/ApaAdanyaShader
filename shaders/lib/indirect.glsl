#include "/lib/scene_trace.glsl"
#include "/lib/reservoir.glsl"
vec4 sampleIndirect(vec2 uv, vec3 vp, vec3 N, vec4 mat, vec2 pixel) {
    vec4 result=vec4(0.0,0.0,0.0,1.0);
    float distToCam=length(vp);
            #if defined(SSAO) || defined(SSGI)
            float rotation=ignDither(pixel)*6.2831853;
            #if defined(TEMPORAL_INDIRECT) && defined(HALF_RES_LIGHTING)
            // Stratified temporal directions converge in the GI/AO history pass.
            rotation+=float(frameCounter%32)*2.39996323;
            #endif
            #endif
            #ifdef SSAO
            if(distToCam<48.0 && mat.b<1.0) {
                float occ=0.0;
                ivec2 depthSize=screenTextureSize(depthtex0);
                vec2 projScale=vec2(gbufferProjection[0][0],gbufferProjection[1][1])/max(-vp.z,1.0)*0.5;
                for(int i=0;i<SSAO_SAMPLES;i++) {
                    float angle=float(i)*2.39996+rotation;
                    float radius=1.5*sqrt((float(i)+0.5)/float(SSAO_SAMPLES));
                    vec2 sampleUV=uv+vec2(cos(angle),sin(angle))*(radius*projScale);
                    if(any(lessThan(sampleUV,vec2(0.0)))||any(greaterThan(sampleUV,vec2(1.0)))) continue;
                    float d=depthScreen(depthtex0,sampleUV,depthSize);
                    if(d>=0.999999) continue;
                    vec3 diff=viewPosition(sampleUV,d)-vp;
                    float d2=dot(diff,diff);
                    if(d2>5.76) continue;
                    float len=sqrt(d2);
                    float nd=dot(N,diff)/max(len,0.001);
                    if(nd>0.10) {
                        float broadFade=1.0-smoothstep(0.1,2.4,len);
                        float contactTerm=1.0-smoothstep(0.04,0.50,len);
                        occ+=(nd-0.10)*(broadFade*0.72+contactTerm*0.48);
                    }
                }
                float aoFade=1.0-smoothstep(32.0,48.0,distToCam);
                result.a*=1.0-(occ/float(SSAO_SAMPLES))*0.84*(1.0-mat.b)*aoFade;
            }
            #endif
            #ifdef SSGI
            if(distToCam<42.0 && GI_STRENGTH>0.0) {
                float distWeight=1.0-smoothstep(24.0,42.0,distToCam);
                vec3 tangent=normalize(cross(N,abs(N.y)<0.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0)));
                vec3 bitangent=cross(N,tangent); vec3 bounce=vec3(0.0);
                #ifdef AA_RESTIR
                bounce=sampleReservoirGI(uv,vp,N,rotation,pixel)*float(GI_SAMPLES);
                #else
                for(int i=0;i<GI_SAMPLES;i++) {
                    float angle=rotation+float(i)*2.39996;
                    float z=sqrt((float(i)+0.5)/float(GI_SAMPLES));
                    float r=sqrt(1.0-z*z);
                    vec3 dir=tangent*(cos(angle)*r)+bitangent*(sin(angle)*r)+N*z;
                    vec2 hit=vec2(0);
                    float confidence=0.0;
                    float coverage=0.0;
                    if(traceScreen(depthtex0,vp+N*0.08,dir,0.18,16,hit,confidence)) {
                        vec3 incoming=textureScreen(colortex0,hit).rgb;
                        vec3 hitN=normalize(textureScreen(colortex1,hit).xyz*2.0-1.0);
                        // Cosine-weighted sampling already includes the receiver cosine/PDF.
                        // Reject the back face of a screen hit instead of multiplying a second cosine.
                        float front=smoothstep(0.0,0.15,dot(hitN,-dir));
                        float luminance=dot(incoming,vec3(0.2126,0.7152,0.0722));
                        incoming*=min(1.0,6.0/max(luminance,1e-4)); // hue-preserving firefly limit
                        coverage=front*edgeFade(hit)*confidence;
                        bounce+=incoming*coverage;
                    }
                    #if defined(AA_VOXELS) || defined(AA_LIGHT_SPACE)
                    // Spend the second-view budget only on missing screen coverage.
                    if(coverage<0.5) {
                        vec3 incoming;
                        if(traceSceneFallback(vp+N*0.08,dir,12,incoming,confidence)) {
                            float luminance=dot(incoming,vec3(0.2126,0.7152,0.0722));
                            incoming*=min(1.0,6.0/max(luminance,1e-4));
                            bounce+=incoming*confidence*(1.0-coverage)*(1.0-smoothstep(0.15,0.5,coverage));
                        }
                    }
                    #endif
                }
                #endif
                vec3 primaryBounce=bounce/float(GI_SAMPLES)*GI_STRENGTH*distWeight;
                // One diffuse bounce. Nonlinear brightening created energy and fireflies.
                result.rgb=primaryBounce;
            }
            #endif
    return result;
}
