#include "/lib/common.glsl"
#include "/lib/atmosphere.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 8 */
/* const int colortex8Format = R16F; */
layout(location=0) out vec4 color;
void main(){
    float shadow=1.0;
    #ifdef CLOUD_SHADOWS
    #ifdef VOLUMETRIC_CLOUDS
    #if !defined(NETHER) && !defined(END)
    vec3 ld=worldDirection(shadowLightPosition);
    if(ld.y>0.04){
        vec2 origin=floor(cameraPosition.xz/128.0)*128.0;
        vec3 p=vec3(origin.x+(texcoord.x-0.5)*2048.0,64.0,origin.y+(texcoord.y-0.5)*2048.0);
        float stepLen=140.0/(ld.y*10.0),optical=0.0;
        p+=ld*((220.0-p.y)/ld.y+stepLen*0.5);
        for(int i=0;i<10;i++){optical+=sampleCloudDensity(p,false)*stepLen; p+=ld*stepLen;}
        shadow=mix(0.48,1.0,exp(-optical*0.035));
    }
    #endif
    #endif
    #endif
    color=vec4(shadow,0,0,1);
}

