// View-space marching against opaque depth. Off-screen rays return no hit.
bool traceScreen(sampler2D depths,vec3 origin,vec3 direction,float stride,int count,out vec2 hitUV) {
    float t=stride, previousT=0.0;
    for(int i=0;i<96;i++) {
        if(i>=count) break;
        vec3 p=origin+direction*t;
        if(p.z>=-near) return false;
        vec4 clip=gbufferProjection*vec4(p,1);
        vec2 uv=clip.xy/clip.w*0.5+0.5;
        if(any(lessThan(uv,vec2(0.002)))||any(greaterThan(uv,vec2(0.998)))) return false;
        float depth=texture(depths,uv).r;
        float sceneZ=viewPosition(uv,depth).z;
        float delta=sceneZ-p.z;
        float thickness=0.18+t*0.018;
        if(depth<0.999999 && delta>0.0 && delta<thickness) {
            float lo=previousT,hi=t;
            for(int j=0;j<5;j++) {
                float mid=(lo+hi)*0.5; vec3 mp=origin+direction*mid;
                vec4 mc=gbufferProjection*vec4(mp,1); vec2 mu=mc.xy/mc.w*0.5+0.5;
                float mz=viewPosition(mu,texture(depths,mu).r).z;
                if(mz>mp.z) hi=mid; else lo=mid;
            }
            vec4 refined=gbufferProjection*vec4(origin+direction*hi,1);
            hitUV=refined.xy/refined.w*0.5+0.5;
            return true;
        }
        previousT=t; t+=stride*(1.0+t*0.075);
    }
    return false;
}
float edgeFade(vec2 uv) { vec2 edge=min(uv,1.0-uv); return smoothstep(0.0,0.08,min(edge.x,edge.y)); }
