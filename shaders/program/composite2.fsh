#include "/lib/common.glsl"
uniform sampler2D colortex4;
in vec2 texcoord;
/* RENDERTARGETS: 5 */
layout(location=0) out vec4 color;
/* const int colortex5Format = RGBA16F; */
void main(){
    vec2 px=4.0/vec2(viewWidth,viewHeight); vec3 sum=vec3(0); float weight=0.0;
    for(int i=-6;i<=6;i++){float w=exp(-float(i*i)/12.0); sum+=texture(colortex4,texcoord+vec2(float(i)*px.x,0)).rgb*w; weight+=w;}
    color=vec4(sum/weight,1);
}

