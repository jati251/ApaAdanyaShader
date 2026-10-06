// Project the ray once; homogeneous coordinates remain linear in ray distance.
float traceSurfaceDepth(sampler2D depths,ivec2 depthSize,ivec2 dhDepthSize,vec2 uv,out bool valid) {
    float d=depthScreen(depths,uv,depthSize);
    valid=d<0.999999;
    if(valid) return viewDepth(uv,d);
    #ifdef AA_TRACE_DH
    #ifndef AA_TRACE_DH_DEPTH
    #define AA_TRACE_DH_DEPTH dhDepthTex1
    #endif
    // Deferred uses live depth; water uses the opaque copy refreshed before translucency.
    float dh=depthScreen(AA_TRACE_DH_DEPTH,uv,dhDepthSize);
    if(dh<0.999999) {
        valid=true;
        return projectedViewDepth(dhProjectionInverse,uv,dh);
    }
    #endif
    return -1e20;
}
ivec2 traceDHDepthSize() {
    #ifdef AA_TRACE_DH
    return screenTextureSize(AA_TRACE_DH_DEPTH);
    #else
    return ivec2(1);
    #endif
}
float traceSurfaceDepth(sampler2D depths,ivec2 depthSize,vec2 uv,out bool valid) {
    return traceSurfaceDepth(depths,depthSize,traceDHDepthSize(),uv,valid);
}
float traceSurfaceDepth(sampler2D depths,vec2 uv,out bool valid) {
    return traceSurfaceDepth(depths,screenTextureSize(depths),uv,valid);
}
bool traceScreen(sampler2D depths,vec3 origin,vec3 direction,float stride,int count,out vec2 hitUV,out float confidence) {
    confidence=0.0;
    ivec2 depthSize=screenTextureSize(depths),dhDepthSize=traceDHDepthSize();
    // Stable travel avoids frame-dependent hit/miss stripes on smooth water.
    float t=stride,previousT=0.0,previousDelta=-1e20;
    vec4 clipOrigin=gbufferProjection*vec4(origin,1.0);
    vec4 clipDirection=gbufferProjection*vec4(direction,0.0);
    for(int i=0;i<96;i++) {
        if(i>=count) break;
        float rayZ=origin.z+direction.z*t;
        if(rayZ>=-near) return false;
        vec4 clip=clipOrigin+clipDirection*t;
        vec2 uv=clip.xy/clip.w*0.5+0.5;
        if(any(lessThan(uv,vec2(0.002))) || any(greaterThan(uv,vec2(0.998)))) return false;
        bool valid;
        float delta=traceSurfaceDepth(depths,depthSize,dhDepthSize,uv,valid)-rayZ;
        float thickness=min(0.18+t*0.008,1.5);
        if(valid && delta>0.0 && (delta<thickness || (previousDelta<=0.0 && previousDelta>-1e19))) {
            float lo=previousT,hi=t;
            for(int j=0;j<6;j++) {
                float mid=(lo+hi)*0.5;
                vec4 mc=clipOrigin+clipDirection*mid;
                vec2 mu=mc.xy/mc.w*0.5+0.5;
                bool midValid;
                float mz=traceSurfaceDepth(depths,depthSize,dhDepthSize,mu,midValid);
                if(midValid && mz>origin.z+direction.z*mid) hi=mid;
                else lo=mid;
            }
            vec4 refined=clipOrigin+clipDirection*hi;
            hitUV=refined.xy/refined.w*0.5+0.5;
            bool hitValid;
            float error=traceSurfaceDepth(depths,depthSize,dhDepthSize,hitUV,hitValid)-(origin.z+direction.z*hi);
            // Refinement can cross a silhouette; recheck the final surface thickness.
            if(hitValid && error>=0.0 && error<thickness) {
                confidence=(1.0-smoothstep(0.35,1.0,error/thickness))
                    *(1.0-smoothstep(0.75,1.0,float(i)/max(float(count-1),1.0)));
                return true;
            }
            // A foreground silhouette can invalidate this bracket. Continue the ray.
        }
        previousDelta=valid?delta:-1e20;
        previousT=t;
        // Reach distant shorelines with the existing sample budget.
        t+=stride+t*0.10;
    }
    return false;
}
bool traceScreen(sampler2D depths,vec3 origin,vec3 direction,float stride,int count,out vec2 hitUV) {
    float confidence;
    return traceScreen(depths,origin,direction,stride,count,hitUV,confidence);
}
float edgeFade(vec2 uv) { vec2 edge=min(uv,1.0-uv); return smoothstep(0.002,0.10,min(edge.x,edge.y)); }
// Screen-Space Ray-Traced Shadow (RT Shadow): traces pixel-perfect contact shadows towards the light source.
float traceScreenShadow(sampler2D depths,ivec2 depthSize,vec3 origin,vec3 lightDirV,float maxDist,int steps) {
    if(lightDirV.z > 0.40) return 0.0;
    ivec2 dhDepthSize=traceDHDepthSize();
    vec4 clipOrigin = gbufferProjection * vec4(origin, 1.0);
    vec4 clipDir = gbufferProjection * vec4(lightDirV, 0.0);
    // Cull subpixel contact rays by projected extent, independent of FOV/resolution.
    // Rays crossing the near plane keep the original trace and clipping behavior.
    vec4 clipEnd=clipOrigin+clipDir*maxDist;
    float detailWeight=1.0;
    if(origin.z<-near && origin.z+lightDirV.z*maxDist<-near
        && clipOrigin.w>0.0 && clipEnd.w>0.0) {
        vec2 travel=(clipEnd.xy/clipEnd.w-clipOrigin.xy/clipOrigin.w)
            *0.5*vec2(viewWidth,viewHeight);
        detailWeight=smoothstep(0.5,1.0,length(travel));
        if(detailWeight<=0.0) return 0.0;
    }
    float stepStride = maxDist / float(steps);
    float jitter = ignDither(gl_FragCoord.xy);
    float t = stepStride * (0.4 + 0.6 * jitter);
    for(int i = 0; i < 16; i++) {
        if(i >= steps) break;
        float rayZ = origin.z + lightDirV.z * t;
        if(rayZ >= -near) break;
        vec4 clip = clipOrigin + clipDir * t;
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        if(any(lessThan(uv, vec2(0.002))) || any(greaterThan(uv, vec2(0.998)))) break;
        bool valid;
        float d = traceSurfaceDepth(depths, depthSize, dhDepthSize, uv, valid);
        float delta = d - rayZ;
        float thickness = min(0.20 + t * 0.06, 0.75);
        if(valid && delta > 0.004 && delta < thickness) {
            float contactWeight = 1.0 - smoothstep(0.0, maxDist, t);
            return contactWeight * edgeFade(uv) * detailWeight;
        }
        t += stepStride;
    }
    return 0.0;
}
