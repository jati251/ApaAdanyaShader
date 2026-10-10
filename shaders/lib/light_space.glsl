#ifndef AA_LIGHT_SPACE_TRACE
#define AA_LIGHT_SPACE_TRACE
#ifdef AA_LIGHT_SPACE
#ifndef AA_LIGHTING
uniform sampler2D shadowtex0;
#endif
uniform sampler2D shadowcolor0,shadowcolor1;

// A second 2.5D view, not a voxel scene. Only accept a front-surface crossing:
// a receiver already behind the sun's first layer must not hit that layer.
bool traceLightSpace(vec3 originV,vec3 directionV,int budget,out vec3 radiance,out float confidence) {
    radiance=vec3(0.0); confidence=0.0;
    vec3 originW=(gbufferModelViewInverse*vec4(originV,1.0)).xyz;
    vec3 directionW=worldDirection(directionV);
    if(length(originW.xz)>shadowDistance*0.8) return false;
    vec4 origin=shadowProjection*shadowModelView*vec4(originW,1.0);
    vec4 direction=shadowProjection*shadowModelView*vec4(directionW,0.0);
    float scale=max(abs(shadowProjection[2][2])*0.1,1e-6);
    float t=0.25,previousT=0.0,previousDelta=1e20;
    ivec2 size=textureSize(shadowtex0,0);
    for(int i=0;i<24;i++) {
        if(i>=budget) break;
        vec4 clip=origin+direction*t;
        vec3 sc=distortShadow(clip.xyz/clip.w)*0.5+0.5;
        if(any(lessThan(sc,vec3(0.002))) || any(greaterThan(sc,vec3(0.998)))) return false;
        ivec2 q=clamp(ivec2(sc.xy*vec2(size)),ivec2(0),size-1);
        float d=texelFetch(shadowtex0,q,0).r;
        float delta=(sc.z-d)/scale;
        float thickness=min(0.12+t*0.006,0.35);
        if(d<0.999999 && previousDelta<=0.0 && delta>0.0) {
            float lo=previousT,hi=t;
            for(int j=0;j<5;j++) {
                float mid=(lo+hi)*0.5;
                vec4 mc=origin+direction*mid;
                vec3 ms=distortShadow(mc.xyz/mc.w)*0.5+0.5;
                ivec2 mq=clamp(ivec2(ms.xy*vec2(size)),ivec2(0),size-1);
                if(ms.z>texelFetch(shadowtex0,mq,0).r) hi=mid; else lo=mid;
            }
            clip=origin+direction*hi;
            sc=distortShadow(clip.xyz/clip.w)*0.5+0.5;
            q=clamp(ivec2(sc.xy*vec2(size)),ivec2(0),size-1);
            delta=(sc.z-texelFetch(shadowtex0,q,0).r)/scale;
            vec4 geometry=texelFetch(shadowcolor1,q,0);
            vec3 n=normalize(geometry.xyz*2.0-1.0);
            float front=smoothstep(0.0,0.15,dot(n,-directionW));
            if(geometry.a>0.5 && delta>=0.0 && delta<thickness && front>0.0) {
                confidence=front*(1.0-smoothstep(0.35,1.0,delta/thickness));
                confidence*=1.0-smoothstep(shadowDistance*0.65,shadowDistance*0.9,length((originW+directionW*hi).xz));
                radiance=texelFetch(shadowcolor0,q,0).rgb;
                return confidence>0.001;
            }
        }
        previousDelta=d<0.999999?delta:-1e20;
        previousT=t;
        t+=0.25+t*0.12;
    }
    return false;
}
#endif
#endif
