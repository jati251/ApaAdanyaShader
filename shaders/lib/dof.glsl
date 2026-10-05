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

float lensDepth(vec2 uv) {
    float d=texture(depthtex0,uv).r;
    if(d<0.999999) return max(-viewPosition(uv,d).z,0.05);
    #ifdef DISTANT_HORIZONS
    float dh=texture(dhDepthTex0,uv).r;
    if(dh<0.999999) {
        vec4 p=dhProjectionInverse*vec4(uv*2.0-1.0,dh*2.0-1.0,1.0);
        return max(-p.z/p.w,0.05);
    }
    #endif
    return 10000.0;
}

bool lensHand(vec2 uv) {
    return texture(depthtex0,uv).r<0.56 && texture(colortex2,uv).a>0.5;
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
    focus=clamp(-viewPosition(vec2(0.5),centerDepthSmooth).z,0.5,10000.0);
    #ifdef DISTANT_HORIZONS
    if(centerDepthSmooth>=0.999999) focus=lensDepth(vec2(0.5));
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
    for(int i=0;i<DOF_SAMPLES;i++) {
        float r=sqrt((float(i)+0.5)/float(DOF_SAMPLES));
        float angle=float(i)*2.39996323;
        vec2 tap=uv+vec2(cos(angle),sin(angle))*r*radius*pixel;
        if(any(lessThan(tap,pixel)) || any(greaterThan(tap,1.0-pixel))) continue;
        if(lensHand(tap)) continue;
        float tapZ=lensDepth(tap);
        float tapCoC=circleOfConfusion(tapZ,focus);
        // Keep focused foreground out of distant bokeh, and backgrounds out of near blur.
        float depthWeight=1.0-smoothstep(0.02,0.15,abs(tapZ-centerZ)/max(centerZ,1.0));
        float sameSide=step(0.0,tapCoC*coc);
        float coverage=smoothstep(r*radius-1.0,r*radius+1.0,abs(tapCoC));
        float w=max(depthWeight,sameSide*coverage*step(centerZ,tapZ));
        sum+=texture(colortex0,tap).rgb*w;
        total+=w;
    }
    return mix(sharp,sum/total,smoothstep(0.75,1.5,radius));
}
#endif
