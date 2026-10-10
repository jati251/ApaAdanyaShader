#include "/lib/common.glsl"
#ifdef VOLUMETRIC_LIGHT
#define AA_VOLUMETRIC_LIGHT
#endif
#include "/lib/atmosphere.glsl"
#include "/lib/lighting.glsl"
#include "/lib/water.glsl"
#include "/lib/volumetric.glsl"
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
        float waterSky=smoothstep(8.0,180.0,float(eyeBrightnessSmooth.y));
        vec3 waterEquil=waterBodyColor(dist,waterSky)*waterSky;
        #ifdef WATER_CAUSTICS
#if (!(defined(NETHER)) && !(defined(END)))
        vec3 wPos=(gbufferModelViewInverse*vec4(vp,1.0)).xyz+cameraPosition;
        float causticFootprint=max(length(dFdx(wPos.xz)),length(dFdy(wPos.xz)))*3.6;
        if(depth<0.999999 && !hand && causticFootprint<0.95 && waterSky>0.0){
            float caustic=waterCaustic(wPos.xz,frameTimeCounter*(0.65*WIND_SPEED),causticFootprint);
            float waterDepthFade=exp(-max(cameraPosition.y-wPos.y,0.0)*0.45);
            vec3 up=vec3(0,1,0);
            float sunVis=shadowVisibility(wPos-cameraPosition,up,max(worldDirection(shadowLightPosition).y,0.0),true)*cloudShadow(wPos);
            c+=vec3(0.095,0.115,0.085)*caustic*waterDepthFade*daylight()*sunVis
                *smoothstep(8.0,180.0,float(eyeBrightnessSmooth.y));
        }
        #endif
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
#if (!(defined(NETHER)) && !(defined(END)))
                float sunDot=dot(rd,sunDirection());
                float forwardScatter=pow(sat(sunDot*0.5+0.5),8.0)*daylight()*(1.0-rainStrength);
                fog+=solarLightColor()*forwardScatter*0.12;
                #endif
                c=mix(c,fog,min(amount,0.98));
            }
        }
        #endif
#if ((defined(VOLUMETRIC_LIGHT) && !(defined(NETHER))) && !(defined(END)))
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
    }
    color=vec4(max(c,vec3(0.0)),1.0);
}
