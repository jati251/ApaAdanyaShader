#include "/lib/common.glsl"
#include "/lib/bloom.glsl"
uniform sampler2D colortex0,colortex4;
#include "/lib/color_grading.glsl"
#include "/lib/taa.glsl"
in vec2 texcoord;
// TAA-off profiles do not write or retain a full-resolution history target.
#ifdef TAA
/* RENDERTARGETS: 0,13 */
/*
const int colortex13Format = RGBA16F;
const bool colortex13Clear = false;
*/
layout(location=1) out vec4 history;
#else
/* RENDERTARGETS: 0 */
#endif
layout(location=0) out vec4 color;
void main(){
    vec3 c=textureScreen(colortex0,texcoord).rgb;
    #ifdef TAA
    float historyDepth=0.0;
    c=applyTAA(texcoord,c,historyDepth);
    // History contains scene-linear color, before lens effects and display grading.
    history=vec4(c,historyDepth);
    #endif
    #ifdef BLOOM
    float bloomScale = BLOOM_STRENGTH;
    #ifdef AUTO_EXPOSURE
    // Dynamic eye adaptation: radiant flare burst when stepping from dark caves into bright sunlight
    float measuredExp = texelFetch(colortex16, ivec2(0), 0).r;
    if(measuredExp > 1.15 && eyeBrightnessSmooth.y > 60) {
        float flareBurst = smoothstep(1.15, 2.6, measuredExp) * smoothstep(60.0, 180.0, float(eyeBrightnessSmooth.y)) * daylight();
        bloomScale *= (1.0 + flareBurst * 1.75);
    }
    #endif
    c+=textureScreen(colortex4,texcoord).rgb*bloomScale;
    #endif
    c=applyColorGrading(c,texcoord);
    color=vec4(c,1.0);
}
