#ifndef AA_TAA
#define AA_TAA
#ifdef TAA
uniform sampler2D colortex13;
#ifndef DEPTH_COLORTEX2_DECLARED
#define DEPTH_COLORTEX2_DECLARED
uniform sampler2D depthtex0,colortex2;
#endif
uniform mat4 gbufferPreviousModelView,gbufferPreviousProjection;
uniform vec3 previousCameraPosition;
#if defined(DISTANT_HORIZONS) && !defined(DH_PROJECTION_INVERSE_DECLARED)
#define DH_PROJECTION_INVERSE_DECLARED
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif

vec3 temporalEncode(vec3 rgb) {
    rgb=max(rgb,vec3(0.0));
    rgb/=1.0+max(rgb.r,max(rgb.g,rgb.b));
    return vec3(dot(rgb,vec3(0.25,0.5,0.25)),(rgb.r-rgb.b)*0.5,(-rgb.r+2.0*rgb.g-rgb.b)*0.25);
}
vec3 temporalDecode(vec3 c) {
    vec3 rgb=max(vec3(c.x+c.y-c.z,c.x+c.z,c.x-c.y-c.z),vec3(0.0));
    return rgb/max(1.0-max(rgb.r,max(rgb.g,rgb.b)),0.0001);
}
vec3 applyTAA(vec2 uv,vec3 currentRGB,out float historyDepth) {
    float depth=depthScreen(depthtex0,uv);
    float mask=textureScreen(colortex2,uv).a;
    bool sky=depth>=0.999999;
    vec3 vp=viewPosition(uv,depth);
    #ifdef DISTANT_HORIZONS
    if(sky) {
        float dh=depthScreen(dhDepthTex0,uv);
        if(dh<0.999999) {
            vec4 p=dhProjectionInverse*vec4(uv*2.0-1.0,dh*2.0-1.0,1.0);
            vp=p.xyz/p.w;
            sky=false;
        }
    }
    #endif
    bool hand=depth<0.56 && mask>0.5;
    historyDepth=hand?-2.0:(sky?-1.0:min(-vp.z,60000.0));
    vec3 delta=cameraPosition-previousCameraPosition;
    if(hand || frameCounter<2 || frameTime<=0.0 || frameTime>0.2 || dot(delta,delta)>4.0) return currentRGB;
    if(abs(gbufferProjection[1][1]-gbufferPreviousProjection[1][1])>0.01) return currentRGB;

    // Sky reprojection uses a direction (w=0), so camera translation has no effect.
    vec4 relative=sky?vec4(mat3(gbufferModelViewInverse)*normalize(vp),0.0)
                     :vec4((gbufferModelViewInverse*vec4(vp,1.0)).xyz+delta,1.0);
    vec4 previousView=gbufferPreviousModelView*relative;
    vec4 previousClip=gbufferPreviousProjection*previousView;
    if(previousClip.w<=0.0) return currentRGB;
    vec2 historyUV=previousClip.xy/previousClip.w*0.5+0.5;
    ivec2 size=screenTextureSize(colortex13);
    vec2 margin=1.0/vec2(size);
    if(any(lessThan(historyUV,margin)) || any(greaterThan(historyUV,1.0-margin))) return currentRGB;

    // Validate depth before interpolation; background history cannot bleed into a new foreground.
    vec2 p=historyUV*vec2(size)-0.5,f=fract(p);
    ivec2 base=ivec2(floor(p));
    vec3 old=vec3(0.0);
    float total=0.0;
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        vec4 tap=texelFetch(colortex13,clamp(base+ivec2(x,y),ivec2(0),size-1),0);
        bool valid=sky?abs(tap.a+1.0)<0.01
                      :(tap.a>0.0 && abs(tap.a+previousView.z)<max(0.06,-previousView.z*0.015));
        if(!valid || any(isnan(tap)) || any(isinf(tap))) continue;
        float weight=(x==0?1.0-f.x:f.x)*(y==0?1.0-f.y:f.y);
        old+=tap.rgb*weight; total+=weight;
    }
    if(total<0.5) return currentRGB;
    old=temporalEncode(old/total);
    vec3 now=temporalEncode(currentRGB),lo=now,hi=now,mean=now,m2=now*now;
    const ivec2 offsets[4]=ivec2[4](ivec2(-1,0),ivec2(1,0),ivec2(0,-1),ivec2(0,1));
    ivec2 currentSize=screenTextureSize(colortex0);
    ivec2 pixel=clamp(ivec2(uv*vec2(currentSize)),ivec2(0),currentSize-1);
    for(int i=0;i<4;i++) {
        vec3 tap=temporalEncode(texelFetch(colortex0,clamp(pixel+offsets[i],ivec2(0),currentSize-1),0).rgb);
        lo=min(lo,tap); hi=max(hi,tap); mean+=tap; m2+=tap*tap;
    }
    mean*=0.2;
    vec3 sigma=sqrt(max(m2*0.2-mean*mean,vec3(0.0)));
    lo=max(lo,mean-1.25*sigma); hi=min(hi,mean+1.25*sigma);
    vec3 clipped=clamp(old,lo,hi);
    float reactive=sat(abs(old.x-now.x)/max(max(old.x,now.x),0.05));
    float movement=length((uv-historyUV)*vec2(size));
    float blend=pow(TAA_BLEND,clamp(frameTime*60.0,0.25,4.0))*exp(-movement*0.025);
    blend*=1.0-smoothstep(0.05,0.35,reactive);
    // Water, translucent surfaces and entities lack per-object motion vectors.
    if(mask>0.1) blend=min(blend,0.15);
    return temporalDecode(mix(now,clipped,blend));
}
#endif
#endif
