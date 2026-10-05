#include "/lib/common.glsl"
#include "/lib/bloom.glsl"
uniform sampler2D colortex4;
in vec2 texcoord;
/* RENDERTARGETS: 5 */
layout(location=0) out vec4 color;
/*
const int colortex5Format = RGBA16F;
*/
void main(){
    #ifdef BLOOM
    color=vec4(blurBloom(colortex4,texcoord,vec2(1.0/float(screenTextureSize(colortex4).x),0.0)),1.0);
    #else
    color=vec4(0.0);
    #endif
}
