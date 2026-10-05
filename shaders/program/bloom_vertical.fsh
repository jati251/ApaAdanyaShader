#include "/lib/common.glsl"
#include "/lib/bloom.glsl"
uniform sampler2D colortex5;
in vec2 texcoord;
/* RENDERTARGETS: 4 */
layout(location=0) out vec4 color;
void main() {
    color=vec4(blurBloom(colortex5,texcoord,vec2(0.0,1.0/float(screenTextureSize(colortex5).y))),1.0);
}
