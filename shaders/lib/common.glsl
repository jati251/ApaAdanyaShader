#ifndef AA_COMMON
#define AA_COMMON
#include "/lib/settings.glsl"
uniform mat4 gbufferModelView, gbufferModelViewInverse;
uniform mat4 gbufferProjection, gbufferProjectionInverse;
uniform mat4 shadowModelView, shadowProjection;
uniform vec3 cameraPosition, sunPosition, shadowLightPosition, fogColor;
uniform float frameTimeCounter, rainStrength, wetness, viewWidth, viewHeight, near, far;
uniform int worldTime, isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
const float PI = 3.14159265;
float sat(float x) { return clamp(x, 0.0, 1.0); }
float hash12(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float hash13(vec3 p) { p=fract(p*0.1031); p+=dot(p,p.yzx+33.33); return fract((p.x+p.y)*p.z); }
float noise3(vec3 p) {
    vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash13(i),hash13(i+vec3(1,0,0)),f.x),mix(hash13(i+vec3(0,1,0)),hash13(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash13(i+vec3(0,0,1)),hash13(i+vec3(1,0,1)),f.x),mix(hash13(i+vec3(0,1,1)),hash13(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float fbm(vec3 p) { return noise3(p)*0.57+noise3(p*2.03)*0.28+noise3(p*4.07)*0.15; }
vec3 viewPosition(vec2 uv,float d) { vec4 p=gbufferProjectionInverse*vec4(uv*2.0-1.0,d*2.0-1.0,1); return p.xyz/p.w; }
vec3 worldDirection(vec3 v) { return normalize(mat3(gbufferModelViewInverse)*v); }
vec3 sunDirection() { return worldDirection(sunPosition); }
float daylight() { return smoothstep(-0.10,0.18,sunDirection().y); }
vec3 lightColor() {
    float elev=abs(sunDirection().y);
    vec3 day=mix(vec3(2.8,0.95,0.28),vec3(3.2,2.85,2.40),smoothstep(0.02,0.40,elev));
    return mix(vec3(0.055,0.085,0.16)*NIGHT_BRIGHTNESS,day,daylight())*(1.0-rainStrength*0.78);
}
vec3 distortShadow(vec3 p) { p.xy/=0.15+length(p.xy)*0.85; p.z*=0.2; return p; }
vec3 waveOffset(vec3 p, float id, float top) {
    #ifdef WAVING_FOLIAGE
    float wind=sin(p.x*0.43+p.z*0.31+frameTimeCounter*1.6)+0.45*sin(p.z*0.91+frameTimeCounter*2.5);
    if (id>1000.5 && id<1001.5) return vec3(wind,0.0,wind*0.4)*0.065*top;
    if (id>1001.5 && id<1002.5) return vec3(wind,sin(p.x+frameTimeCounter)*0.3,wind*0.6)*0.035;
    #endif
    return vec3(0);
}
#endif

