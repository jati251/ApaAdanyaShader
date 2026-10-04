#include "/lib/common.glsl"
uniform sampler2D colortex0;
in vec2 texcoord;
layout(location=0) out vec4 color;
float luma(vec3 c){return dot(c,vec3(0.299,0.587,0.114));}
void main(){
    vec2 px=1.0/vec2(viewWidth,viewHeight);
    vec3 c=texture(colortex0,texcoord).rgb;
    #ifdef FXAA
    vec3 nw=texture(colortex0,texcoord+vec2(-1,-1)*px).rgb;
    vec3 ne=texture(colortex0,texcoord+vec2(1,-1)*px).rgb;
    vec3 sw=texture(colortex0,texcoord+vec2(-1,1)*px).rgb;
    vec3 se=texture(colortex0,texcoord+vec2(1,1)*px).rgb;
    float m=luma(c), nwl=luma(nw),nel=luma(ne),swl=luma(sw),sel=luma(se);
    float low=min(m,min(min(nwl,nel),min(swl,sel))),high=max(m,max(max(nwl,nel),max(swl,sel)));
    if(high-low>max(0.035,high*0.125)){
        vec2 dir=vec2(-(nwl+nel-swl-sel),nwl+swl-nel-sel);
        float reduce=max((nwl+nel+swl+sel)*0.03125,0.0078125);
        dir=clamp(dir/(min(abs(dir.x),abs(dir.y))+reduce),vec2(-8),vec2(8))*px;
        vec3 a=0.5*(texture(colortex0,texcoord-dir/6.0).rgb+texture(colortex0,texcoord+dir/6.0).rgb);
        vec3 b=a*0.5+0.25*(texture(colortex0,texcoord-dir*0.5).rgb+texture(colortex0,texcoord+dir*0.5).rgb);
        c=(luma(b)<low||luma(b)>high)?a:b;
    }
    #endif
    c+=(hash12(gl_FragCoord.xy)-0.5)/255.0;
    color=vec4(clamp(c,0.0,1.0),1);
}
