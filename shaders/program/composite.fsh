#include "/lib/common.glsl"
#ifdef VOLUMETRIC_LIGHT
#define AA_VOLUMETRIC_LIGHT
#endif
#include "/lib/atmosphere.glsl"
#include "/lib/lighting.glsl"
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjectionInverse;
#endif
uniform sampler2D colortex0,colortex2,depthtex0;
in vec2 texcoord;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
void main(){
    vec3 c=textureScreen(colortex0,texcoord).rgb;
    float depth=textureScreen(depthtex0,texcoord).r;
    vec3 vp=viewPosition(texcoord,depth), rd=worldDirection(normalize(vp));
    float dist=depth>=0.999999?far:min(length(vp),far);
    bool isDH=false;
    #ifdef DISTANT_HORIZONS
    float dhSolidD=textureScreen(dhDepthTex0,texcoord).r;
    float dhTransD=textureScreen(dhDepthTex1,texcoord).r;
    float dhDepth=min(dhSolidD,dhTransD);
    if(depth>=0.999999 && dhDepth<1.0){
        isDH=true;
        vec4 clipDH=vec4(texcoord*2.0-1.0,dhDepth*2.0-1.0,1.0);
        vec4 vpDH=dhProjectionInverse*clipDH;
        vp=vpDH.xyz/vpDH.w;
        rd=worldDirection(normalize(vp));
        dist=length(vp);
    }
    #endif
    bool hand=textureScreen(colortex2,texcoord).a>0.5 && depth<0.56;
    if(isEyeInWater==1){
        // Absorption along the eye-to-surface path.
        vec3 trans=exp(-vec3(0.24,0.075,0.038)*dist/WATER_CLARITY);
        vec3 waterEquil=vec3(0.005,0.085,0.15)*mix(0.15,1.0,daylight());
        #ifdef WATER_CAUSTICS
        if(depth<0.999999 && !hand){
            vec3 wPos=(gbufferModelViewInverse*vec4(vp,1.0)).xyz+cameraPosition;
            float ct=frameTimeCounter*1.6;
            float ca1=sin(wPos.x*2.2+wPos.z*1.5+ct*1.3);
            float ca2=cos(wPos.x*1.7-wPos.z*2.4-ct*1.1);
            float ca3=sin(wPos.x*3.5+wPos.z*0.9+ct*2.0);
            float caustic=pow(sat(1.0-abs(ca1+ca2)*0.5),5.0)*0.7+pow(sat(1.0-abs(ca2+ca3)*0.5),4.0)*0.3;
            float waterDepthFade=exp(-max(cameraPosition.y-wPos.y,0.0)*0.28);
            c+=vec3(0.04,0.18,0.22)*caustic*waterDepthFade*daylight()*smoothstep(8.0,180.0,float(eyeBrightnessSmooth.y));
        }
        #endif
        c=c*trans+waterEquil*(1.0-trans);
    }else if(isEyeInWater==2){
        c=mix(c,vec3(2.0,0.22,0.012),1.0-exp(-dist*1.5));
    }else if(!hand){
        #ifdef FOG_ENABLED
        if(FOG_DENSITY > 0.001){
            float altitude=cameraPosition.y+rd.y*dist*0.5;
            float heightFactor=clamp(exp(-max(altitude-110.0,0.0)*0.003),0.55,1.0);
            float fogOpt=pow(dist*0.00062*FOG_DENSITY,1.22)*heightFactor;
            if(rainStrength>0.01) fogOpt+=dist*rainStrength*0.0035;
            float amount=1.0-exp(-fogOpt);
            #ifdef NETHER
            amount=1.0-exp(-dist*0.016*FOG_DENSITY);
            #elif defined(END)
            amount=1.0-exp(-dist*0.002*FOG_DENSITY);
            #endif
            if((depth<0.999999 || isDH) && amount>0.001){
                vec3 fog=skyRadiance(normalize(vec3(rd.x,max(rd.y,0.02),rd.z)));
                #if !defined(NETHER) && !defined(END)
                float sunDot=dot(rd,sunDirection());
                float forwardScatter=pow(sat(sunDot*0.5+0.5),8.0)*daylight()*(1.0-rainStrength);
                fog+=lightColor()*forwardScatter*0.30;
                #endif
                c=mix(c,fog,min(amount,0.98));
            }
        }
        #endif
        #if defined(VOLUMETRIC_LIGHT) && !defined(NETHER) && !defined(END)
        float outdoor=smoothstep(8.0,150.0,float(eyeBrightnessSmooth.y));
        if(outdoor>0.001){
            float rayLength=min(dist,100.0);
            float sunPhase=pow(sat(dot(rd,worldDirection(shadowLightPosition))),24.0);
            float phase=0.025+sunPhase*0.28;
            float lightFactor=phase*(1.0-exp(-rayLength*0.0015*FOG_DENSITY))*outdoor;
            if(lightFactor>0.0005){
                float sum=0.0;
                float jitter=ignDither(gl_FragCoord.xy);
                // Optimized exponential step clustering: concentrates precision near camera
                for(int i=0;i<VL_SAMPLES;i++){
                    float stepFrac=pow((float(i)+jitter)/float(VL_SAMPLES),1.30);
                    vec3 p=rd*rayLength*stepFrac;
                    sum+=shadowVisibility(p,vec3(0.0),1.0,false);
                }
                c+=lightColor()*(sum/float(VL_SAMPLES))*lightFactor;
            }
        }
        #endif
    }
    color=vec4(max(c,vec3(0.0)),1.0);
}


