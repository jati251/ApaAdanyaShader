#include "/lib/common.glsl"
uniform sampler2D colortex0;
in vec2 texcoord;
/* RENDERTARGETS: 14 */
/*
const int colortex14Format=RGBA16F;
*/
layout(location=0) out vec4 color;
#if UPSCALE_QUALITY > 0
#define FSR_EASU_F 1
#include "/lib/vendor/fsr1/fsr1_fp32.glsl"
vec4 cachedA, cachedB, cachedC, cachedD;
vec2 cachedP = vec2(-99999.0);
vec4 gatherChannel(vec2 uv,int component) {
    if(uv != cachedP) {
        cachedP = uv;
        ivec2 base=ivec2(floor(uv*vec2(textureSize(colortex0,0))-0.5));
        ivec2 limit=screenTextureSize(colortex0)-1;
        cachedA=texelFetch(colortex0,clamp(base+ivec2(0,1),ivec2(0),limit),0);
        cachedB=texelFetch(colortex0,clamp(base+ivec2(1,1),ivec2(0),limit),0);
        cachedC=texelFetch(colortex0,clamp(base+ivec2(1,0),ivec2(0),limit),0);
        cachedD=texelFetch(colortex0,clamp(base,ivec2(0),limit),0);
    }
    return vec4(cachedA[component],cachedB[component],cachedC[component],cachedD[component]);
}
vec4 FsrEasuRF(vec2 p) { return gatherChannel(p,0); }
vec4 FsrEasuGF(vec2 p) { return gatherChannel(p,1); }
vec4 FsrEasuBF(vec2 p) { return gatherChannel(p,2); }
#endif
void main() {
    #if UPSCALE_QUALITY > 0
    vec2 activeSize=vec2(screenTextureSize(colortex0));
    vec2 allocation=vec2(textureSize(colortex0,0));
    uvec4 c0,c1,c2,c3;
    FsrEasuCon(c0,c1,c2,c3,activeSize.x,activeSize.y,allocation.x,allocation.y,allocation.x,allocation.y);
    vec3 c;
    FsrEasuF(c,uvec2(gl_FragCoord.xy),c0,c1,c2,c3);
    color=vec4(clamp(c,0.0,1.0),1.0);
    #else
    color=texture(colortex0,texcoord);
    #endif
}
