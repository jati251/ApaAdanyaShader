#include "/lib/common.glsl"
#include "/lib/atmosphere.glsl"
uniform sampler2D depthtex0;
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0,dhDepthTex1;
#endif
in vec2 texcoord;
/* RENDERTARGETS: 9 */
/*
const int colortex9Format = RGBA16F;
*/
layout(location=0) out vec4 layer;
void main() {
    // March a whole cloud layer only where at least one covered pixel is sky.
    bool sky=false;
    vec2 size=vec2(textureSize(depthtex0,0));
    for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
        vec2 uv=texcoord+(vec2(x,y)-0.5)/size;
        bool clear=texture(depthtex0,uv).r>=0.999999;
        #ifdef DISTANT_HORIZONS
        clear=clear && min(texture(dhDepthTex0,uv).r,texture(dhDepthTex1,uv).r)>=0.999999;
        #endif
        sky=sky || clear;
    }
    layer=vec4(0.0,0.0,0.0,-1.0);
    if(!sky) return;
    vec3 rd=worldDirection(viewPosition(texcoord,1.0));
    vec2 pixel=texcoord*size;
    #ifdef TEMPORAL_CLOUDS
    pixel+=vec2(5.588238)*float(frameCounter%64);
    #endif
    layer=cloudLayer(rd,pixel);
}
