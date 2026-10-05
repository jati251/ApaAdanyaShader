vec4 sampleIndirect(vec2 uv, vec3 vp, vec3 N, vec4 mat, vec2 pixel) {
    vec4 result=vec4(0.0,0.0,0.0,1.0);
    float distToCam=length(vp);
            #if defined(SSAO) || defined(SSGI)
            float rotation=ignDither(pixel)*6.2831853;
            #endif
            #ifdef SSAO
            if(distToCam<48.0) {
                float occ=0.0;
                vec2 projScale=vec2(gbufferProjection[0][0],gbufferProjection[1][1])/max(-vp.z,1.0)*0.5;
                for(int i=0;i<SSAO_SAMPLES;i++) {
                    float angle=float(i)*2.39996+rotation;
                    float radius=1.5*sqrt((float(i)+0.5)/float(SSAO_SAMPLES));
                    vec2 uv=uv+vec2(cos(angle),sin(angle))*(radius*projScale);
                    if(any(lessThan(uv,vec2(0.0)))||any(greaterThan(uv,vec2(1.0)))) continue;
                    float d=texture(depthtex0,uv).r;
                    vec3 diff=viewPosition(uv,d)-vp;
                    float len=length(diff);
                    occ+=max(dot(N,diff/max(len,0.001))-0.10,0.0)*(1.0-smoothstep(0.1,2.4,len))*step(d,0.99999);
                }
                float aoFade=1.0-smoothstep(32.0,48.0,distToCam);
                result.a*=1.0-(occ/float(SSAO_SAMPLES))*0.84*(1.0-mat.b)*aoFade;
            }
            #endif
            #ifdef SSGI
            if(distToCam<42.0) {
                float distWeight=1.0-smoothstep(24.0,42.0,distToCam);
                vec3 tangent=normalize(cross(N,abs(N.y)<0.9?vec3(0.0,1.0,0.0):vec3(1.0,0.0,0.0)));
                vec3 bitangent=cross(N,tangent); vec3 bounce=vec3(0.0);
                for(int i=0;i<GI_SAMPLES;i++) {
                    float angle=rotation+float(i)*2.39996;
                    float z=sqrt((float(i)+0.5)/float(GI_SAMPLES));
                    float r=sqrt(1.0-z*z);
                    vec3 dir=normalize(tangent*cos(angle)*r+bitangent*sin(angle)*r+N*z);
                    vec2 hit;
                    if(traceScreen(depthtex0,vp+N*0.08,dir,0.18,10,hit)) {
                        vec3 incoming=texture(colortex0,hit).rgb;
                        vec3 hitN=normalize(texture(colortex1,hit).xyz*2.0-1.0);
                        bounce+=min(incoming,vec3(3.0))*max(dot(hitN,-dir),0.0)*edgeFade(hit);
                    }
                }
                result.rgb=bounce/float(GI_SAMPLES)*GI_STRENGTH*distWeight;
            }
            #endif
    return result;
}
