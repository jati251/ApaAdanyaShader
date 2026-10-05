// Project the ray once; homogeneous coordinates remain linear in ray distance.
bool traceScreen(sampler2D depths,vec3 origin,vec3 direction,float stride,int count,out vec2 hitUV) {
    float dither=ignDither(gl_FragCoord.xy);
    float t=stride*(0.75+0.5*dither),previousT=0.0,previousDelta=-1e20;
    vec4 clipOrigin=gbufferProjection*vec4(origin,1.0);
    vec4 clipDirection=gbufferProjection*vec4(direction,0.0);
    for(int i=0;i<96;i++) {
        if(i>=count) break;
        float rayZ=origin.z+direction.z*t;
        if(rayZ>=-near) return false;
        vec4 clip=clipOrigin+clipDirection*t;
        vec2 uv=clip.xy/clip.w*0.5+0.5;
        if(any(lessThan(uv,vec2(0.002))) || any(greaterThan(uv,vec2(0.998)))) return false;
        float depth=textureScreen(depths,uv).r;
        float delta=viewDepth(uv,depth)-rayZ;
        float thickness=min(0.22+t*0.025,1.0);
        if(depth<0.999999 && delta>0.0 && (delta<thickness || (previousDelta<=0.0 && previousDelta>-1e19))) {
            float lo=previousT,hi=t;
            for(int j=0;j<4;j++) {
                float mid=(lo+hi)*0.5;
                vec4 mc=clipOrigin+clipDirection*mid;
                vec2 mu=mc.xy/mc.w*0.5+0.5;
                float md=textureScreen(depths,mu).r;
                if(md<0.999999 && viewDepth(mu,md)>origin.z+direction.z*mid) hi=mid;
                else lo=mid;
            }
            vec4 refined=clipOrigin+clipDirection*hi;
            hitUV=refined.xy/refined.w*0.5+0.5;
            float hitDepth=textureScreen(depths,hitUV).r;
            float error=viewDepth(hitUV,hitDepth)-(origin.z+direction.z*hi);
            // Refinement can cross a silhouette; recheck the final surface thickness.
            if(hitDepth<0.999999 && error>=0.0 && error<thickness) return true;
            // A foreground silhouette can invalidate this bracket. Continue the ray.
        }
        previousDelta=depth<0.999999?delta:-1e20;
        previousT=t;
        t+=stride*(1.0+float(i)*0.035);
    }
    return false;
}
float edgeFade(vec2 uv) { vec2 edge=min(uv,1.0-uv); return smoothstep(0.002,0.08,min(edge.x,edge.y)); }
