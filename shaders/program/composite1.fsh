#include "/lib/common.glsl"
uniform sampler2D colortex0;
in vec2 texcoord;
/* RENDERTARGETS: 4 */
layout(location=0) out vec4 color;
/* const int colortex4Format = RGBA16F; */
void main(){
    #ifdef BLOOM
    vec3 sum=vec3(0.0); vec2 px=1.0/vec2(viewWidth,viewHeight);
    for(int x=-2;x<=2;x++) for(int y=-2;y<=2;y++){
        vec3 c=texture(colortex0,texcoord+vec2(float(x),float(y))*px*3.0).rgb;
        float l=max(max(c.r,c.g),c.b);
        sum+=c*max(l-1.0,0.0)/max(l,0.001);
    }
    sum/=25.0;
    color=vec4(sum,1.0);
    #else
    color=vec4(0.0);
    #endif
}

