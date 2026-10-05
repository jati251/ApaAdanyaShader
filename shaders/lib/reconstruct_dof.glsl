#if defined(DOF) && defined(HALF_RES_DOF)
uniform sampler2D colortex12;
vec3 reconstructDOF(vec2 uv,vec3 sharp) {
    if(lensHand(uv)) return sharp;
    float z=lensDepth(uv),focus=lensFocus();
    float coc=circleOfConfusion(z,focus);
    if(abs(coc)<0.75) return sharp;
    if(abs(coc)<2.0) return depthOfField(uv,sharp);
    ivec2 size=screenTextureSize(colortex12);
    vec2 p=uv*vec2(size)-0.5,f=fract(p);
    ivec2 base=ivec2(floor(p));
    vec3 sum=vec3(0.0);
    float total=0.0;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 q=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 tap=texelFetch(colortex12,q,0);
        if(tap.a<=0.0) continue;
        float tapCoC=circleOfConfusion(tap.a,focus);
        float w=(x==0?1.0-f.x:f.x)*(y==0?1.0-f.y:f.y);
        w*=1.0-smoothstep(0.01,0.05,abs(tap.a-z)/max(z,1.0));
        w*=1.0-smoothstep(0.25,1.0,abs(tapCoC-coc));
        sum+=tap.rgb*w; total+=w;
    }
    if(total<0.75) return depthOfField(uv,sharp);
    return sum/total;
}
#endif
