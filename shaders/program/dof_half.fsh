#include "/lib/common.glsl"
uniform sampler2D colortex0;
#include "/lib/dof.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 12 */
/*
const int colortex12Format = RGBA16F;
*/
layout(location=0) out vec4 gathered;
void main() {
    gathered=vec4(textureScreen(colortex0,texcoord).rgb,0.0);
    #ifdef DOF
    float d=textureScreen(depthtex0,texcoord).r;
    if(d<0.56 && textureScreen(colortex2,texcoord).a>0.5) return;
    float z=lensDepthFromValue(texcoord,d);
    // Smaller circles are gathered at native resolution by the resolve pass.
    if(abs(circleOfConfusion(z,lensFocus()))<2.0) return;
    gathered=vec4(depthOfField(texcoord,gathered.rgb),min(z,60000.0));
    #endif
}
