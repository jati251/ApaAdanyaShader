#ifdef DOF
#ifndef DEPTH_COLORTEX2_DECLARED
#define DEPTH_COLORTEX2_DECLARED
uniform sampler2D depthtex0,colortex2;
#endif
uniform float centerDepthSmooth;
#if defined(DISTANT_HORIZONS) && !defined(DH_PROJECTION_INVERSE_DECLARED)
#define DH_PROJECTION_INVERSE_DECLARED
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif

float lensDepthFromValue(vec2 uv, float d) {
    if(d<0.999999) return max(-viewDepth(uv,d),0.05);
    #ifdef DISTANT_HORIZONS
    float dh=depthScreen(dhDepthTex0,uv);
    if(dh<0.999999) {
        return max(-projectedViewDepth(dhProjectionInverse,uv,dh),0.05);
    }
    #endif
    return 10000.0;
}

float lensDepth(vec2 uv) {
    return lensDepthFromValue(uv, depthScreen(depthtex0,uv));
}

bool lensHand(vec2 uv) {
    return depthScreen(depthtex0,uv)<0.56 && textureScreen(colortex2,uv).a>0.5;
}

float circleOfConfusion(float z,float focus) {
    float focal=DOF_FOCAL_LENGTH*0.001;
    float aperture=focal/DOF_FSTOP;
    // Thin lens, 24 mm sensor height; signed radius in screen pixels.
    float coc=aperture*focal*(z-focus)/(z*max(focus-focal,0.01));
    return clamp(coc*viewHeight/0.048,-DOF_MAX_RADIUS,DOF_MAX_RADIUS);
}

float lensFocus() {
    float focus=DOF_FOCUS_DISTANCE;
    #ifdef DOF_AUTOFOCUS
    #if UPSCALE_QUALITY > 0
    // Iris samples the allocation center; our active viewport has a different center.
    focus=clamp(lensDepth(vec2(0.5)),0.5,10000.0);
    #else
    focus=clamp(-viewDepth(vec2(0.5),centerDepthSmooth),0.5,10000.0);
    #ifdef DISTANT_HORIZONS
    if(centerDepthSmooth>=0.999999) focus=lensDepth(vec2(0.5));
    #endif
    #endif
    #endif
    return focus;
}

vec3 depthOfField(vec2 uv,vec3 sharp) {
    if(lensHand(uv)) return sharp;
    float focus=lensFocus();
    float centerZ=lensDepth(uv);
    float coc=circleOfConfusion(centerZ,focus);
    float radius=abs(coc);
    if(radius<0.75) return sharp;
    vec2 pixel=1.0/vec2(viewWidth,viewHeight);
    vec3 sum=sharp;
    float total=1.0;
    ivec2 depthSize=screenTextureSize(depthtex0);
    for(int i=0;i<DOF_SAMPLES;i++) {
        float r=sqrt((float(i)+0.5)/float(DOF_SAMPLES));
        float angle=float(i)*2.39996323;
        vec2 tap=uv+vec2(cos(angle),sin(angle))*r*radius*pixel;
        if(any(lessThan(tap,pixel)) || any(greaterThan(tap,1.0-pixel))) continue;
        float tapD=depthScreen(depthtex0,tap,depthSize);
        if(tapD<0.56 && textureScreen(colortex2,tap).a>0.5) continue;
        float tapZ=lensDepthFromValue(tap,tapD);
        float tapCoC=circleOfConfusion(tapZ,focus);
        // Keep focused foreground out of distant bokeh, and backgrounds out of near blur.
        float depthWeight=1.0-smoothstep(0.02,0.15,abs(tapZ-centerZ)/max(centerZ,1.0));
        float sameSide=step(0.0,tapCoC*coc);
        float coverage=smoothstep(r*radius-1.0,r*radius+1.0,abs(tapCoC));
        // Background bokeh must not spill through a terrain silhouette.
        float backgroundGuard=1.0-smoothstep(0.15,0.40,max(tapZ-centerZ,0.0)/max(centerZ,1.0));
        float w=max(depthWeight,sameSide*coverage*step(centerZ,tapZ))*backgroundGuard;
        sum+=textureScreen(colortex0,tap).rgb*w;
        total+=w;
    }
    return mix(sharp,sum/total,smoothstep(0.75,1.5,radius));
}
#endif
