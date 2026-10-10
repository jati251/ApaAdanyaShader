#ifndef AA_CLOUD_SHADOW
#define AA_CLOUD_SHADOW
#include "/lib/cloud_weather.glsl"
uniform sampler2D colortex8;
float cloudShadow(vec3 world) {
    #if defined(CLOUD_SHADOWS) && CLOUDS > 0 && !defined(NETHER) && !defined(END)
    vec3 ld=worldDirection(shadowLightPosition);
    if(ld.y<=0.04 || world.y>=CLOUD_ALT_BASE) return 1.0;
    vec2 uv=cloudShadowUV(world,ld);
    float fade=smoothstep(0.44,0.50,max(abs(uv.x-0.5),abs(uv.y-0.5)));
    if(fade>=1.0) return 1.0;
    float value=texture(colortex8,clamp(uv,vec2(0.002),vec2(0.998))).r;
    return mix(value,1.0,fade);
    #else
    return 1.0;
    #endif
}
#endif
