#include "/lib/common.glsl"
uniform sampler2D gtexture;
in vec2 texcoord;
in vec4 glcolor;
flat in float materialId;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
void main(){
    #ifdef SHADOWS
    if(materialId>1002.5 && materialId<1003.5) discard;
    #ifdef SHADOW_ALPHA_TEST
    if(materialId>1000.5 && materialId<1002.5){
        if(texture(gtexture,texcoord).a*glcolor.a < 0.1) discard;
    }
    #endif
    color=vec4(1.0);
    #else
    discard;
    #endif
}
