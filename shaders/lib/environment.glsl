#include "/lib/atmosphere.glsl"
uniform sampler2D colortex7;
vec3 environmentRadiance(vec3 rd){
    vec2 uv=vec2(atan(rd.z,rd.x)/(2.0*PI)+0.5,asin(clamp(rd.y,-1.0,1.0))/PI+0.5);
    // The sky cache is generated before terrain. It is safe to sample in water.
    return texture(colortex7,vec2(fract(uv.x),clamp(uv.y,0.001,0.999))).rgb;
}
