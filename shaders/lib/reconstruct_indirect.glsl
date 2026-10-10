#ifdef HALF_RES_LIGHTING
uniform sampler2D colortex12;
#ifdef AA_SVGF
uniform sampler2D aaDenoiseA;
uniform bool aaDenoiseReady;
#endif
vec4 reconstructIndirect(vec2 uv,vec3 vp,vec3 N,vec4 mat) {
    #if defined(SSGI) && defined(SSAO)
    const float maxDistance=max(48.0,GI_DISTANCE);
    #elif defined(SSGI)
    const float maxDistance=GI_DISTANCE;
    #else
    const float maxDistance=48.0;
    #endif
    if(dot(vp,vp)>=maxDistance*maxDistance) return vec4(0.0,0.0,0.0,1.0);
    ivec2 size=screenTextureSize(colortex12);
    ivec2 depthSize=screenTextureSize(depthtex0);
    vec2 p=uv*vec2(size)-0.5,f=fract(p);
    ivec2 base=ivec2(floor(p));
    vec4 sum=vec4(0.0);
    float total=0.0;
    vec4 bestTap=vec4(0.0,0.0,0.0,1.0);
    float bestScore=-1.0;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 q=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 tap;
        #ifdef AA_SVGF
        if(aaDenoiseReady) tap=texelFetch(aaDenoiseA,q,0);
        else
        #endif
        tap=texelFetch(colortex12,q,0);
        if(tap.a<0.0) continue;
        vec2 coord=(vec2(q)+0.5)/vec2(size);
        float tapZ=viewDepth(coord,depthScreen(depthtex0,coord,depthSize));
        float depthWeight=1.0-smoothstep(0.01,0.05,abs(tapZ-vp.z)/max(-vp.z,1.0));
        // Do not fetch normals/materials, or offer a nearest fallback, from
        // another depth layer. The old fallback ignored depth entirely.
        if(depthWeight<=0.0) continue;
        vec3 tapN=normalize(textureScreen(colortex1,coord).xyz*2.0-1.0);
        vec4 tapMat=textureScreen(colortex2,coord);
        float w=(x==0?1.0-f.x:f.x)*(y==0?1.0-f.y:f.y);
        float normalDot=dot(N,tapN);
        float emissionWeight=1.0-smoothstep(0.02,0.1,abs(tapMat.b-mat.b));
        float score=depthWeight*max(normalDot,0.0)*emissionWeight;
        if(score>bestScore){bestScore=score;bestTap=tap;}
        w*=depthWeight*smoothstep(0.94,0.995,normalDot)*emissionWeight;
        sum+=tap*w; total+=w;
    }
    // Normalize valid partial coverage; avoid rerunning all rays at every edge pixel.
    if(total>=0.001) return sum/total;
    if(bestScore>0.0) return bestTap;
    return vec4(0.0,0.0,0.0,1.0);
}
#endif
