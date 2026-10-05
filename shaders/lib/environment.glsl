#include "/lib/atmosphere.glsl"
uniform sampler2D colortex7;
vec3 environmentRadiance(vec3 rd){
    vec2 uv=vec2(atan(rd.z,rd.x)/(2.0*PI)+0.5,asin(clamp(rd.y,-1.0,1.0))/PI+0.5);
    // The sky cache is generated before terrain. It is safe to sample in water.
    ivec2 size=textureSize(colortex7,0);
    float x=fract(uv.x)*float(size.x)-0.5;
    int left=int(floor(x));
    int x0=(left+size.x)%size.x,x1=(left+1+size.x)%size.x;
    float y=clamp(uv.y,0.5/float(size.y),1.0-0.5/float(size.y));
    vec3 a=texture(colortex7,vec2((float(x0)+0.5)/float(size.x),y)).rgb;
    vec3 b=texture(colortex7,vec2((float(x1)+0.5)/float(size.x),y)).rgb;
    return mix(a,b,fract(x));
}
