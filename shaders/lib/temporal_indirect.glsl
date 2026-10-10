#ifndef AA_TEMPORAL_INDIRECT
#define AA_TEMPORAL_INDIRECT
#ifdef TEMPORAL_INDIRECT
uniform sampler2D colortex17;
#ifndef AA_RESTIR
uniform sampler2D colortex18;
#endif
#ifndef AA_PREVIOUS_INDIRECT_UNIFORMS
#define AA_PREVIOUS_INDIRECT_UNIFORMS
uniform mat4 gbufferPreviousModelView,gbufferPreviousProjection;
uniform vec3 previousCameraPosition;
#endif
#ifdef AA_SVGF
uniform sampler2D colortex19;
vec4 aaIndirectMoments=vec4(0);
#endif
vec4 stabilizeIndirect(vec2 uv,vec3 vp,vec3 N,vec4 mat,vec4 current) {
    #ifdef AA_SVGF
    float luminance=dot(current.rgb,vec3(0.2126,0.7152,0.0722));
    aaIndirectMoments=vec4(luminance,luminance*luminance,0.0,1.0);
    vec4 oldMoments=vec4(0);
    #endif
    vec3 travel=cameraPosition-previousCameraPosition;
    if(mat.a>0.1 || frameCounter<2 || frameTime<=0.0 || frameTime>0.2 || dot(travel,travel)>4.0
       || abs(gbufferProjection[1][1]-gbufferPreviousProjection[1][1])>0.01) return current;
    vec4 previousView=gbufferPreviousModelView*vec4((gbufferModelViewInverse*vec4(vp,1)).xyz+travel,1);
    vec4 clip=gbufferPreviousProjection*previousView;
    if(clip.w<=0.0) return current;
    vec2 historyUV=clip.xy/clip.w*0.5+0.5;
    ivec2 size=screenTextureSize(colortex17);
    vec2 margin=1.0/vec2(size);
    if(any(lessThan(historyUV,margin)) || any(greaterThan(historyUV,1.0-margin))) return current;
    vec2 p=historyUV*vec2(size)-0.5,f=fract(p);
    ivec2 base=ivec2(floor(p));
    vec4 history=vec4(0);float total=0.0;
    vec3 nw=worldDirection(N);
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 q=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 geometry=texelFetch(colortex18,q,0),tap=texelFetch(colortex17,q,0);
        if(geometry.a<=0.0 || abs(geometry.a+previousView.z)>max(0.08,-previousView.z*0.015)
           || dot(nw,geometry.xyz)<0.95 || any(isnan(tap)) || any(isinf(tap)) || tap.a<0.0) continue;
        float w=(x==0?1.0-f.x:f.x)*(y==0?1.0-f.y:f.y);
        history+=tap*w;total+=w;
        #ifdef AA_SVGF
        vec4 moments=texelFetch(colortex19,q,0);
        if(moments.a>0.0 && !any(isnan(moments)) && !any(isinf(moments))) oldMoments+=moments*w;
        #endif
    }
    if(total<0.5) return current;
    history/=total;
    history=clamp(history,vec4(0),vec4(6,6,6,1));
    float movement=length((uv-historyUV)*vec2(size));
    float blend=pow(0.88,clamp(frameTime*60.0,0.25,4.0))*exp(-movement*0.10);
    blend*=1.0-smoothstep(0.08,0.30,abs(history.a-current.a));
    // Responsive radiance clipping prevents a vanished emitter leaving a long trail.
    // Keep headroom for the sparse GI estimator; geometry/AO remain separate tests.
    float currentLuma=dot(current.rgb,vec3(0.2126,0.7152,0.0722));
    float historyLuma=dot(history.rgb,vec3(0.2126,0.7152,0.0722));
    float radianceLimit=max(0.15,currentLuma*3.0);
    history.rgb*=min(1.0,radianceLimit/max(historyLuma,1e-4));
    blend*=mix(1.0,0.35,smoothstep(0.2,1.0,max(historyLuma-currentLuma,0.0)));
    #ifdef AA_SVGF
    oldMoments/=total;
    float historyLength=clamp(oldMoments.a+1.0,1.0,32.0);
    float momentBlend=min(blend,1.0-1.0/historyLength);
    vec2 moments=mix(vec2(luminance,luminance*luminance),oldMoments.xy,momentBlend);
    aaIndirectMoments=vec4(moments,max(moments.y-moments.x*moments.x,0.0),historyLength);
    #endif
    return mix(current,history,blend);
}
#endif
#endif
