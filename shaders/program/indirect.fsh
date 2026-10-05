#include "/lib/common.glsl"
#include "/lib/trace.glsl"
uniform sampler2D colortex0,colortex1,colortex2,depthtex0;
#include "/lib/indirect.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 12 */
/*
const int colortex12Format = RGBA16F;
*/
layout(location=0) out vec4 indirect;
void main() {
    float d=texture(depthtex0,texcoord).r;
    vec4 mat=texture(colortex2,texcoord);
    indirect=vec4(0.0,0.0,0.0,-1.0);
    if(d>=0.999999 || mat.a>0.5) return;
    vec3 vp=viewPosition(texcoord,d);
    vec3 N=normalize(texture(colortex1,texcoord).xyz*2.0-1.0);
    indirect=sampleIndirect(texcoord,vp,N,mat,texcoord*vec2(viewWidth,viewHeight));
}
