#include "/lib/common.glsl"
in vec4 glcolor;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
void main() {
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
    color=vec4(pow(max(glcolor.rgb,vec3(0.0)),vec3(2.2)),glcolor.a);
}
