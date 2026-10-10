#include "/lib/common.glsl"
#include "/lib/atmosphere.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 8 */
/*
const int colortex8Format = R16F;
*/
layout(location=0) out vec4 color;
void main(){
    float shadow=1.0;
    #if defined(CLOUD_SHADOWS) && (CLOUDS > 0) && !defined(NETHER) && !defined(END)
    vec3 ld=worldDirection(shadowLightPosition);
    if(ld.y>0.04){
        vec2 origin=floor(cameraPosition.xz/128.0)*128.0;
        vec3 p=vec3(origin.x+(texcoord.x-0.5)*CLOUD_SHADOW_SPAN,64.0,origin.y+(texcoord.y-0.5)*CLOUD_SHADOW_SPAN);
        vec3 ground=p;
        #if CLOUDS == 1
        // One sheet lookup per atlas texel; no per-receiver cloud noise or raymarch.
        vec2 cloudPlane=ground.xz+ld.xz*((CLOUD_ALT_BASE-ground.y)/ld.y);
        float footprint=CLOUD_SHADOW_SPAN/128.0*FAST_CLOUD_SCALE;
        float optical=fastCloudDensity(cloudPlane,footprint)*1.8;
        #else
        float stepLen=CLOUD_ALT_THICK/(ld.y*8.0),optical=0.0;
        p+=ld*((CLOUD_ALT_BASE-p.y)/ld.y+stepLen*0.5);
        for(int i=0;i<8;i++){optical+=sampleCloudDensity(p,false)*stepLen*CLOUD_EXTINCTION; p+=ld*stepLen;}
        #if CLOUD_LAYERS >= 2
        vec2 mid=ground.xz+ld.xz*((CLOUD_MID_ALT-ground.y)/ld.y);
        optical+=sheetCloudDensity(mid,false)*34.0*0.045/max(ld.y,0.12);
        #endif
        #if CLOUD_LAYERS >= 3
        vec2 high=ground.xz+ld.xz*((CLOUD_HIGH_ALT-ground.y)/ld.y);
        optical+=sheetCloudDensity(high,true)*10.0*0.032/max(ld.y,0.12);
        #endif
        #endif
        shadow=mix(1.0-CLOUD_SHADOW_STRENGTH,1.0,exp(-optical));
        shadow=mix(1.0,shadow,smoothstep(0.04,0.12,ld.y));
    }
    #endif
    color=vec4(shadow,0.0,0.0,1.0);
}
