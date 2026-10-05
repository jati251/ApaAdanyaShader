#include "/lib/common.glsl"
#ifdef VOLUMETRIC_LIGHT
#define AA_VOLUMETRIC_LIGHT
#endif
#include "/lib/atmosphere.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform mat4 dhProjectionInverse;
#endif
uniform sampler2D colortex0,colortex2,depthtex0;
in vec2 texcoord;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
void main(){
    vec3 c=textureScreen(colortex0,texcoord).rgb;
    float depth=depthScreen(depthtex0,texcoord);
    vec3 vp=viewPosition(texcoord,depth), rd=worldDirection(normalize(vp));
    float dist=depth>=0.999999?far:min(length(vp),far);
    bool isDH=false;
    #ifdef DISTANT_HORIZONS
    // Combined depth already includes current DH terrain and water.
    float dhDepth=depthScreen(dhDepthTex0,texcoord);
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
            float caustic=waterCaustic(wPos.xz,frameTimeCounter*(0.65*WIND_SPEED));
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
            // Clear-air perspective leaves near materials intact instead of lifting their blacks.
            float fogOpt=clearAirOpticalDepth(dist,altitude);
            if(rainStrength>0.01) fogOpt+=dist*rainStrength*0.0035;
            float amount=1.0-exp(-fogOpt);
            #ifdef NETHER
            amount=1.0-exp(-dist*0.016*FOG_DENSITY);
            #elif defined(END)
            amount=1.0-exp(-dist*0.002*FOG_DENSITY);
            #endif
            if((depth<0.999999 || isDH) && amount>0.001){
                // Fog scatters atmospheric radiance, not the sun/moon disk or lens corona.
                vec3 fog=atmosphereBackground(normalize(vec3(rd.x,max(rd.y,0.02),rd.z)));
                #if !defined(NETHER) && !defined(END)
                float sunDot=dot(rd,sunDirection());
                float forwardScatter=pow(sat(sunDot*0.5+0.5),8.0)*daylight()*(1.0-rainStrength);
                fog+=lightColor()*forwardScatter*0.12;
                #endif
                c=mix(c,fog,min(amount,0.98));
            }
        }
        #endif
        #if defined(VOLUMETRIC_LIGHT) && !defined(NETHER) && !defined(END)
        float outdoor=smoothstep(8.0,150.0,float(eyeBrightnessSmooth.y));
        if(outdoor>0.001){
            float rayLength=min(dist,100.0);
            // Physically-based Henyey-Greenstein atmospheric aerosol forward scattering (g = 0.72)
            float cosTheta=dot(rd,worldDirection(shadowLightPosition));
            float denom=1.5184-1.44*cosTheta;
            float hg=0.4816*inversesqrt(max(denom*denom*denom,0.00001));
            float phase=0.030+hg*0.22;
            float lightFactor=phase*(1.0-exp(-rayLength*0.0015*FOG_DENSITY))*outdoor;
            if(lightFactor>0.0005){
                float sum=0.0, weightSum=0.0;
                float jitter=ignDither(gl_FragCoord.xy);
                // Optimized exponential step clustering with height-dependent ground mist density
                for(int i=0;i<VL_SAMPLES;i++){
                    float stepFrac=pow((float(i)+jitter)/float(VL_SAMPLES),1.30);
                    vec3 p=rd*rayLength*stepFrac;
                    float hExtinction=exp(-max((cameraPosition.y+p.y)-64.0,0.0)*0.012);
                    sum+=shadowVisibility(p,vec3(0.0),1.0,false)*hExtinction;
                    weightSum+=hExtinction;
                }
                c+=lightColor()*(sum/max(weightSum,0.001))*lightFactor;
            }
        }
        #endif
        #if !defined(NETHER) && !defined(END)
        // Volumetric atmospheric dust motes & airborne spores (The Last of Us signature aesthetic)
        if(dist > 0.8 && depth < 0.999999) {
            float moteDist = min(dist, 14.0);
            float moteJitter = ignDither(gl_FragCoord.xy);
            float motes = 0.0;
            for(int m = 0; m < 3; m++) {
                float mt = (float(m) + moteJitter) / 3.0;
                float dSample = 1.0 + mt * (moteDist - 1.0);
                vec3 pWorld = cameraPosition + rd * dSample;
                vec3 drift = vec3(frameTimeCounter * 0.06, sin(frameTimeCounter * 0.08 + pWorld.x) * 0.05, frameTimeCounter * 0.04);
                vec3 cell = floor((pWorld + drift) * 1.8);
                vec3 f = fract((pWorld + drift) * 1.8) - 0.5;
                float h = hash13(cell);
                if(h > 0.94) {
                    float spark = smoothstep(0.18, 0.02, length(f));
                    spark *= smoothstep(1.0, 2.5, dSample) * (1.0 - smoothstep(10.0, 14.0, dSample));
                    motes += spark * (h - 0.94) * 16.0;
                }
            }
            if(motes > 0.001) {
                vec3 moteLight = mix(vec3(0.08, 0.12, 0.18), lightColor(), daylight() * smoothstep(20.0, 180.0, float(eyeBrightnessSmooth.y)));
                c += moteLight * motes * 0.28;
            }
        }
        #endif
    }
    color=vec4(max(c,vec3(0.0)),1.0);
}


