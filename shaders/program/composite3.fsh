#include "/lib/common.glsl"
#include "/lib/bloom.glsl"
uniform sampler2D colortex0,colortex5;
#include "/lib/dof.glsl"
#include "/lib/reconstruct_dof.glsl"
#include "/lib/color_grading.glsl"
#include "/lib/taa.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 0,13 */
/*
const int colortex13Format = RGBA16F;
const bool colortex13Clear = false;
*/
layout(location=0) out vec4 color;
layout(location=1) out vec4 history;
void main(){
    vec3 c=texture(colortex0,texcoord).rgb;
    #ifdef DOF
    #ifdef HALF_RES_DOF
    c=reconstructDOF(texcoord,c);
    #else
    c=depthOfField(texcoord,c);
    #endif
    #endif
    #ifdef BLOOM
    c+=blurBloom(colortex5,texcoord,vec2(0.0,4.0/viewHeight))*BLOOM_STRENGTH;
    #endif
    c=applyColorGrading(c,texcoord);
    #ifdef TAA
    c=applyTAA(texcoord,c);
    #endif
    color=vec4(c,1.0);
    history=vec4(c,1.0);
}
