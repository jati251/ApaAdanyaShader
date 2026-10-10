#include "/lib/common.glsl"
#ifdef VOLUMETRIC_LIGHT
#define AA_VOLUMETRIC_LIGHT
#endif
#include "/lib/atmosphere.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/volumetric.glsl"
#define AA_SMOKE_RECONSTRUCT
#include "/lib/smoke.glsl"
uniform sampler2D colortex0;
in vec2 texcoord;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
void main(){
    vec3 c=textureScreen(colortex0,texcoord).rgb;
    vec3 vp,rd;float dist,depth;bool hand,isDH;
    volumetricScene(texcoord,vp,rd,dist,depth,hand,isDH);
    if(isEyeInWater==1){
        // Absorption along the eye-to-surface path in murky natural freshwater
        vec3 trans=exp(-waterAbsorption()*dist);
        vec3 waterEquil=vec3(0.018,0.032,0.020)*mix(0.15,1.0,daylight())*smoothstep(8.0,180.0,float(eyeBrightnessSmooth.y));
        #ifdef WATER_CAUSTICS
        if(depth<0.999999 && !hand){
            vec3 wPos=(gbufferModelViewInverse*vec4(vp,1.0)).xyz+cameraPosition;
            float caustic=waterCaustic(wPos.xz,mod(frameTimeCounter,6283.1853)*(0.65*WIND_SPEED));
            float waterDepthFade=exp(-max(cameraPosition.y-wPos.y,0.0)*0.45);
            c+=vec3(0.080,0.095,0.045)*caustic*waterDepthFade*daylight()*smoothstep(8.0,180.0,float(eyeBrightnessSmooth.y));
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
                fog+=solarLightColor()*forwardScatter*0.12;
                #endif
                c=mix(c,fog,min(amount,0.98));
            }
        }
        #endif
        #if defined(VOLUMETRIC_LIGHT) && !defined(NETHER) && !defined(END)
        float lightFactor=volumetricFactor(rd,dist);
        if(lightFactor>0.0005) {
            #ifdef HALF_RES_LIGHTING
            float visibility=reconstructVolumetric(texcoord,rd,dist,vp,depth,isDH);
            #else
            float visibility=volumetricVisibility(rd,dist,gl_FragCoord.xy);
            #endif
            c+=lightColor()*visibility*lightFactor;
        }
        #endif
        #if !defined(NETHER) && !defined(END) && defined(VOLUMETRIC_LIGHT)
        // Volumetric atmospheric dust motes & airborne spores (The Last of Us signature aesthetic)
        if(dist > 0.8 && depth < 0.999999) {
            float moteDist = min(dist, 14.0);
            float moteJitter = ignDither(gl_FragCoord.xy);
            float motes = 0.0;
            for(int m = 0; m < 3; m++) {
                float mt = (float(m) + moteJitter) / 3.0;
                float dSample = 1.0 + mt * (moteDist - 1.0);
                // Both visibility fades are exactly zero outside this interval.
                if(dSample<=1.0 || dSample>=14.0) continue;
                vec3 pWorld = cameraPosition + rd * dSample;
                vec3 drift = vec3(frameTimeCounter * 0.06, sin(frameTimeCounter * 0.08 + pWorld.x) * 0.05, frameTimeCounter * 0.04);
                vec3 cell = floor((pWorld + drift) * 1.8);
                vec3 f = fract((pWorld + drift) * 1.8) - 0.5;
                float h = hash13(cell);
                if(h > 0.94) {
                    float spark = 1.0-smoothstep(0.02, 0.18, length(f));
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
    #ifdef AA_SMOKE
    if(isEyeInWater==0 && !hand && smokePresent()) {
        vec4 smoke=reconstructSmoke(texcoord,rd,dist,vp,depth,isDH);
        c=c*(1.0-smoke.a)+smoke.rgb;
    }
    #endif
    color=vec4(max(c,vec3(0.0)),1.0);
}
