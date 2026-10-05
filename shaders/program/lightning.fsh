#include "/lib/common.glsl"
uniform int entityId;
in vec4 glcolor;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
void main(){
    #if UPSCALE_QUALITY > 0
    if(any(greaterThanEqual(gl_FragCoord.xy,vec2(viewWidth,viewHeight)))) discard;
    #endif
    vec3 radiance=srgbToLinear(glcolor.rgb);
    // This pass also draws dragon death beams; retain their supplied color.
    if(entityId==1100) radiance=vec3(9.0,11.0,15.0);
    color=vec4(radiance,glcolor.a);
}
