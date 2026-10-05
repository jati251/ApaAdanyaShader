#if defined(CLOUD_RECONSTRUCTION) && CLOUDS == 2 && !defined(NETHER) && !defined(END)
#ifdef TEMPORAL_CLOUDS
uniform sampler2D colortex10;
#define AA_CLOUD_BUFFER colortex10
#else
uniform sampler2D colortex9;
#define AA_CLOUD_BUFFER colortex9
#endif
vec4 reconstructClouds(vec2 uv,vec3 rd) {
    ivec2 size=screenTextureSize(AA_CLOUD_BUFFER);
    vec2 p=uv*vec2(size)-0.5, f=fract(p);
    ivec2 base=ivec2(floor(p));
    vec4 sum=vec4(0.0);
    float total=0.0;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 q=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 tap=texelFetch(AA_CLOUD_BUFFER,q,0);
        float weight=(x==0?1.0-f.x:f.x)*(y==0?1.0-f.y:f.y);
        if(tap.a<0.0) continue;
        sum+=tap*weight;
        total+=weight;
    }
    if(total<0.25) return cloudLayer(rd,gl_FragCoord.xy);
    return sum/total;
}
#endif
