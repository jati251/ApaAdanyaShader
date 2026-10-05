#include "/lib/common.glsl"
#if UPSCALE_QUALITY > 0
#include "/lib/fsr_rcas.glsl"
in vec2 texcoord;
layout(location=0) out vec4 color;
void main() {
    ivec2 pixel=ivec2(gl_FragCoord.xy);
    vec3 c=texelFetch(colortex14,pixel,0).rgb;
    if(UPSCALE_SHARPNESS>0.0) {
        uvec4 config;
        FsrRcasCon(config,2.0-2.0*UPSCALE_SHARPNESS);
        FsrRcasF(c.r,c.g,c.b,uvec2(pixel),config);
    }
    color=vec4(clamp(c,0.0,1.0),1.0);
}
#else
#include "/program/post.fsh"
#endif
