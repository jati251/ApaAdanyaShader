#include "/lib/common.glsl"
uniform sampler2D colortex0;
in vec2 texcoord;
/* RENDERTARGETS: 4 */
layout(location=0) out vec4 color;
/*
const int colortex4Format = RGBA16F;
*/
vec3 bloomSample(vec2 uv) {
    vec3 c=textureScreen(colortex0,clamp(uv,vec2(0.001),vec2(0.999))).rgb;
    float brightness=max(c.r,max(c.g,c.b));
    float knee=clamp(brightness-0.5,0.0,1.0);
    float contribution=max(brightness-1.0,knee*knee*0.5);
    return c*(contribution/max(brightness,0.0001));
}
void main(){
    #ifdef BLOOM
    vec2 px=1.0/vec2(viewWidth,viewHeight);
    vec3 sum=bloomSample(texcoord)*0.125;
    for(int x=-1;x<=1;x+=2) for(int y=-1;y<=1;y+=2) {
        vec2 offset=vec2(float(x),float(y))*px;
        sum+=bloomSample(texcoord+offset)*0.125;
        sum+=bloomSample(texcoord+offset*2.0)*0.03125;
    }
    sum+=(bloomSample(texcoord+vec2(2.0*px.x,0.0))+bloomSample(texcoord-vec2(2.0*px.x,0.0))
         +bloomSample(texcoord+vec2(0.0,2.0*px.y))+bloomSample(texcoord-vec2(0.0,2.0*px.y)))*0.0625;
    color=vec4(sum,1.0);
    #else
    color=vec4(0.0);
    #endif
}
