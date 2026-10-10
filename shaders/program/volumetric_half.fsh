#include "/lib/common.glsl"
#include "/lib/lighting.glsl"
#define AA_VL_MULTIPLIER 2
#include "/lib/volumetric.glsl"
#include "/lib/smoke.glsl"
in vec2 texcoord;
#ifdef AA_SMOKE
/* RENDERTARGETS: 12,21 */
layout(location=1) out vec4 smoke;
/* const int colortex21Format = RGBA16F; */
#else
/* RENDERTARGETS: 12 */
#endif
/*
const int colortex12Format = RGBA16F;
*/
layout(location=0) out vec4 color;
void main() {
    color=vec4(-1.0,0.0,0.0,0.0);
    #ifdef AA_SMOKE
    smoke=vec4(0.0);
    #endif
    #if (defined(AA_SMOKE) || (defined(VOLUMETRIC_LIGHT) && defined(HALF_RES_LIGHTING))) && !defined(NETHER) && !defined(END)
    if(isEyeInWater!=0) return;
    vec3 vp,rd;float dist,depth;bool hand,isDH;
    volumetricScene(texcoord,vp,rd,dist,depth,hand,isDH);
    if(hand) {color.b=3.0;return;}
    float visibility=1.0;
    #if defined(VOLUMETRIC_LIGHT) && defined(HALF_RES_LIGHTING)
    if(volumetricFactor(rd,dist)>0.0005)
        visibility=volumetricVisibility(rd,dist,floor(texcoord*vec2(viewWidth,viewHeight))+0.5);
    #endif
    color=vec4(visibility,dist,isDH?2.0:(depth>=0.999999?0.0:1.0),-vp.z);
    #ifdef AA_SMOKE
    smoke=renderSmoke(rd,dist);
    #endif
    #endif
}
