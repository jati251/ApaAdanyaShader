#include "/lib/common.glsl"
uniform sampler2D colortex0,colortex16;
uniform vec3 previousCameraPosition;
in vec2 texcoord;
/* RENDERTARGETS: 16 */
/*
const int colortex16Format=RGBA16F;
const bool colortex16Clear=false;
*/
layout(location=0) out vec4 metering;
void main() {
    // One fragment, 64 scene-linear samples. Geometric mean suppresses isolated emitters.
    float sum=0.0,total=0.0;
    for(int y=0;y<8;y++) for(int x=0;x<8;x++) {
        vec2 uv=(vec2(x,y)+0.5)/8.0;
        vec3 c=max(textureScreen(colortex0,uv).rgb,vec3(0.0));
        float l=clamp(dot(c,vec3(0.2126,0.7152,0.0722)),0.001,128.0);
        float w=exp(-dot(uv-0.5,uv-0.5)*5.0);
        sum+=log2(l)*w;total+=w;
    }
    float average=exp2(sum/total);
    float target=clamp(0.18/max(average,0.001),0.35,3.0);
    vec4 old=texelFetch(colortex16,ivec2(0),0);
    vec3 travel=cameraPosition-previousCameraPosition;
    bool valid=frameCounter>1 && old.r>=0.35 && old.r<=3.0 && !any(isnan(old)) && !any(isinf(old))
        && frameTime>0.0 && frameTime<0.2 && dot(travel,travel)<64.0;
    float previous=valid?old.r:target;
    // Bright adaptation is faster than the return to darkness. Blend in exposure stops.
    float rate=target<previous?3.0:1.2;
    float blend=1.0-exp(-max(frameTime,0.0)*rate);
    float exposure=exp2(mix(log2(previous),log2(target),blend));
    metering=vec4(exposure,average,0.0,1.0);
}
