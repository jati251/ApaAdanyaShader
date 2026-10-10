#ifndef AA_VOLUMETRIC
#define AA_VOLUMETRIC
uniform sampler2D depthtex0,colortex2;
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif
void volumetricScene(vec2 uv,out vec3 vp,out vec3 rd,out float dist,out float depth,out bool hand,out bool isDH) {
    depth=depthScreen(depthtex0,uv);
    vp=viewPosition(uv,depth);
    rd=worldDirection(vp);
    dist=depth>=0.999999?far:min(length(vp),far);
    isDH=false;
    #ifdef DISTANT_HORIZONS
    if(depth>=0.999999) {
        float dhDepth=depthScreen(dhDepthTex0,uv);
        if(dhDepth<1.0) {
            isDH=true;
            vec4 p=dhProjectionInverse*vec4(uv*2.0-1.0,dhDepth*2.0-1.0,1.0);
            vp=p.xyz/p.w;rd=worldDirection(vp);dist=length(vp);
        }
    }
    #endif
    hand=textureScreen(colortex2,uv).a>0.5 && depth<0.56;
}
#if defined(VOLUMETRIC_LIGHT) && !defined(NETHER) && !defined(END)
float volumetricFactor(vec3 rd,float dist) {
    float outdoor=smoothstep(8.0,150.0,float(eyeBrightnessSmooth.y));
    float cosTheta=dot(rd,worldDirection(shadowLightPosition));
    float denom=1.5184-1.44*cosTheta;
    float hg=0.4816*inversesqrt(max(denom*denom*denom,0.00001));
    return (0.030+hg*0.22)*(1.0-exp(-min(dist,100.0)*0.0015*FOG_DENSITY))*outdoor;
}
#ifndef AA_VL_MULTIPLIER
#define AA_VL_MULTIPLIER 1
#endif
float volumetricVisibility(vec3 rd,float dist,vec2 pixel) {
    float rayLength=min(dist,100.0),sum=0.0,total=0.0;
    float jitter=ignDither(pixel);
    // A directional ray is linear in shadow clip space. Project once per ray.
    vec4 origin=shadowProjection*shadowModelView[3];
    vec4 direction=shadowProjection*(shadowModelView*vec4(rd,0.0));
    float horizontal=length(rd.xz);
    for(int i=0;i<VL_SAMPLES*AA_VL_MULTIPLIER;i++) {
        float distance=rayLength*pow((float(i)+jitter)/float(VL_SAMPLES*AA_VL_MULTIPLIER),1.30);
        float extinction=exp(-max(cameraPosition.y+rd.y*distance-64.0,0.0)*0.012);
        float visibility=1.0;
        #ifdef SHADOWS
        if(shadowDistance>0.0 && horizontal*distance<=shadowDistance) {
            vec4 clip=origin+direction*distance;
            vec3 sc=distortShadow(clip.xyz/clip.w)*0.5+0.5;
            if(all(greaterThanEqual(sc,vec3(0.002))) && all(lessThanEqual(sc,vec3(0.998)))) {
                float fade=smoothstep(shadowDistance*0.8,shadowDistance,horizontal*distance);
                visibility=mix(step(sc.z-0.00010,texture(shadowtex0,sc.xy).r),1.0,fade);
            }
        }
        #endif
        sum+=visibility*extinction;total+=extinction;
    }
    return sum/max(total,0.001);
}
#ifdef HALF_RES_LIGHTING
uniform bool aaVLReady;
uniform sampler2D colortex12;
float reconstructVolumetric(vec2 uv,vec3 rd,float dist,vec3 vp,float depth,bool isDH) {
    if(!aaVLReady) return volumetricVisibility(rd,dist,gl_FragCoord.xy);
    ivec2 size=screenTextureSize(colortex12);
    vec2 p=uv*vec2(size)-0.5,f=fract(p);
    ivec2 base=ivec2(floor(p));
    float sum=0.0,total=0.0;
    float category=isDH?2.0:(depth>=0.999999?0.0:1.0);
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        ivec2 q=clamp(base+ivec2(x,y),ivec2(0),size-1);
        vec4 tap=texelFetch(colortex12,q,0);
        if(tap.r<0.0 || tap.b!=category) continue;
        float w=(x==0?1.0-f.x:f.x)*(y==0?1.0-f.y:f.y);
        // Reject foreground/background crossings; unsupported edges keep full tracing.
        w*=1.0-smoothstep(0.005,0.02,abs(tap.a+vp.z)/max(-vp.z,1.0));
        sum+=tap.r*w;total+=w;
    }
    if(total<0.5) return volumetricVisibility(rd,dist,gl_FragCoord.xy);
    return sum/total;
}
#endif
#endif
#endif
