#include "/lib/common.glsl"
#include "/lib/atmosphere.glsl"
in vec2 texcoord;
/* RENDERTARGETS: 7 */
/*
const int colortex7Format = RGBA16F;
*/
layout(location=0) out vec4 color;
void main(){
    float azimuth=(texcoord.x-0.5)*2.0*PI,elevation=(texcoord.y-0.5)*PI;
    vec3 rd=vec3(cos(azimuth)*cos(elevation),sin(elevation),sin(azimuth)*cos(elevation));
    vec3 sky=skyRadiance(rd);
    color=vec4(min(sky,vec3(6.0)),1.0);
}
