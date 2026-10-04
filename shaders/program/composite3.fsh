#include "/lib/common.glsl"
uniform sampler2D colortex0,colortex5;
in vec2 texcoord;
/* RENDERTARGETS: 0 */
layout(location=0) out vec4 color;
vec3 film(vec3 x){return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.0,1.0);}
void main(){
    vec3 c=texture(colortex0,texcoord).rgb;
    #ifdef BLOOM
    vec2 px=4.0/vec2(viewWidth,viewHeight); vec3 bloom=vec3(0); float weight=0.0;
    for(int i=-6;i<=6;i++){float w=exp(-float(i*i)/12.0); bloom+=texture(colortex5,texcoord+vec2(0,float(i)*px.y)).rgb*w; weight+=w;}
    c+=bloom/weight*BLOOM_STRENGTH;
    #endif
    float exposure=EXPOSURE*mix(1.25,0.90,daylight());
    c=pow(film(c*exposure),vec3(1.0/2.2));
    float luminance=dot(c,vec3(0.2126,0.7152,0.0722));
    c=mix(vec3(luminance),c,COLOR_SATURATION);
    c=clamp((c-0.5)*COLOR_CONTRAST+0.5,0.0,1.0);
    color=vec4(c,1);
}

