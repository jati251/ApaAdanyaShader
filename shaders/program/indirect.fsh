#include "/lib/common.glsl"
#include "/lib/trace.glsl"
uniform sampler2D colortex0,colortex1,colortex2,depthtex0;
#include "/lib/indirect.glsl"
#include "/lib/temporal_indirect.glsl"
in vec2 texcoord;
#ifdef TEMPORAL_INDIRECT
/* RENDERTARGETS: 12,17,18 */
layout(location=1) out vec4 indirectHistory;
layout(location=2) out vec4 geometryHistory;
/*
const int colortex17Format=RGBA16F;
const int colortex18Format=RGBA16F;
const bool colortex17Clear=false;
const bool colortex18Clear=false;
*/
#else
/* RENDERTARGETS: 12 */
#endif
/*
const int colortex12Format = RGBA16F;
*/
layout(location=0) out vec4 indirect;
void main() {
    float d=depthScreen(depthtex0,texcoord);
    vec4 mat=textureScreen(colortex2,texcoord);
    indirect=vec4(0.0,0.0,0.0,-1.0);
    #ifdef TEMPORAL_INDIRECT
    indirectHistory=indirect;
    geometryHistory=vec4(0);
    #endif
    if(d>=0.999999 || mat.a>0.5) return;
    vec3 vp=viewPosition(texcoord,d);
    vec3 N=normalize(textureScreen(colortex1,texcoord).xyz*2.0-1.0);
    indirect=sampleIndirect(texcoord,vp,N,mat,texcoord*vec2(viewWidth,viewHeight));
    #ifdef TEMPORAL_INDIRECT
    indirect=stabilizeIndirect(texcoord,vp,N,mat,indirect);
    indirectHistory=indirect;
    geometryHistory=mat.a>0.1?vec4(0):vec4(worldDirection(N),min(-vp.z,60000.0));
    #endif
}
