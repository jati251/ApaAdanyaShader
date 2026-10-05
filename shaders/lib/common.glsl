#ifndef AA_COMMON
#define AA_COMMON
#include "/lib/settings.glsl"
uniform mat4 gbufferModelView, gbufferModelViewInverse;
uniform mat4 gbufferProjection, gbufferProjectionInverse;
uniform mat4 shadowModelView, shadowProjection;
uniform vec3 cameraPosition, sunPosition, shadowLightPosition, fogColor;
uniform float frameTimeCounter, rainStrength, wetness, viewWidth, viewHeight, near, far;
uniform float frameTime;
uniform int worldTime, isEyeInWater, frameCounter;
uniform ivec2 eyeBrightnessSmooth;
#if UPSCALE_QUALITY == 1
#define AA_RENDER_SCALE 0.76923077
#elif UPSCALE_QUALITY == 2
#define AA_RENDER_SCALE 0.66666667
#elif UPSCALE_QUALITY == 3
#define AA_RENDER_SCALE 0.58823529
#else
#define AA_RENDER_SCALE 1.0
#endif
vec4 scaleSceneClip(vec4 clip,vec2 targetFraction) {
    #if UPSCALE_QUALITY > 0
    vec2 allocation=max(floor(vec2(viewWidth,viewHeight)*targetFraction),vec2(1.0));
    vec2 scale=max(floor(allocation*AA_RENDER_SCALE),vec2(1.0))/allocation;
    clip.xy=(clip.xy+clip.w)*scale-clip.w;
    #endif
    return clip;
}
ivec2 screenTextureSize(sampler2D source) {
    return max(ivec2(floor(vec2(textureSize(source,0))*AA_RENDER_SCALE)),ivec2(1));
}
vec4 textureScreen(sampler2D source,vec2 uv) {
    #if UPSCALE_QUALITY > 0
    vec2 allocation=vec2(textureSize(source,0)),activeSize=vec2(screenTextureSize(source));
    return texture(source,clamp(uv*activeSize,vec2(0.5),activeSize-0.5)/allocation);
    #else
    return texture(source,uv);
    #endif
}
// These macros keep all scene-space radii and fragment coordinates in render pixels.
#if UPSCALE_QUALITY > 0
#define viewWidth floor(viewWidth*AA_RENDER_SCALE)
#define viewHeight floor(viewHeight*AA_RENDER_SCALE)
#endif
const float PI = 3.14159265;
float sat(float x) { return clamp(x, 0.0, 1.0); }
float hash12(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise2D(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash12(i),hash12(i+vec2(1.0,0.0)),f.x),mix(hash12(i+vec2(0.0,1.0)),hash12(i+vec2(1.0,1.0)),f.x),f.y);
}
float hash13(vec3 p) { p=fract(p*0.1031); p+=dot(p,p.yzx+33.33); return fract((p.x+p.y)*p.z); }
float noise3D(vec3 p) {
    vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash13(i),hash13(i+vec3(1.0,0.0,0.0)),f.x),mix(hash13(i+vec3(0.0,1.0,0.0)),hash13(i+vec3(1.0,1.0,0.0)),f.x),f.y),mix(mix(hash13(i+vec3(0.0,0.0,1.0)),hash13(i+vec3(1.0,0.0,1.0)),f.x),mix(hash13(i+vec3(0.0,1.0,1.0)),hash13(i+vec3(1.0,1.0,1.0)),f.x),f.y),f.z);
}
float ignDither(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
vec3 viewPosition(vec2 uv,float d) { vec4 p=gbufferProjectionInverse*vec4(uv*2.0-1.0,d*2.0-1.0,1.0); return p.xyz/p.w; }
float viewDepth(vec2 uv,float d) {
    vec4 clip=vec4(uv*2.0-1.0,d*2.0-1.0,1.0);
    // Only z/w are needed by ray intersection tests.
    return dot(vec4(gbufferProjectionInverse[0][2],gbufferProjectionInverse[1][2],gbufferProjectionInverse[2][2],gbufferProjectionInverse[3][2]),clip)
         / dot(vec4(gbufferProjectionInverse[0][3],gbufferProjectionInverse[1][3],gbufferProjectionInverse[2][3],gbufferProjectionInverse[3][3]),clip);
}
vec3 worldDirection(vec3 v) { return normalize(mat3(gbufferModelViewInverse)*v); }
vec3 sunDirection() { return worldDirection(sunPosition); }
float daylight() { return smoothstep(-0.10,0.18,sunDirection().y); }
vec3 lightColor() {
    #if defined(NETHER) || defined(END)
    return vec3(0.0);
    #else
    float elev=abs(sunDirection().y);
    vec3 day=mix(vec3(3.20,1.25,0.32),vec3(2.85,2.52,2.05),smoothstep(0.02,0.38,elev));
    return mix(vec3(0.055,0.085,0.16)*NIGHT_BRIGHTNESS,day,daylight())*(1.0-rainStrength*0.78);
    #endif
}
vec3 distortShadow(vec3 p) { p.xy/=0.15+length(p.xy)*0.85; p.z*=0.2; return p; }
vec3 waveOffset(vec3 p, float id, float top) {
    #ifdef WAVING_FOLIAGE
    float t = frameTimeCounter * WIND_SPEED;
    float wind=sin(p.x*0.43+p.z*0.31+t*1.6)+0.45*sin(p.z*0.91+t*2.5);
    #ifdef WAVING_PLANTS
    if (id>1000.5 && id<1001.5) return vec3(wind,0.0,wind*0.4)*0.065*top;
    #endif
    #ifdef WAVING_LEAVES
    if (id>1001.5 && id<1002.5) return vec3(wind,sin(p.x+t)*0.3,wind*0.6)*0.035;
    #endif
    #endif
    return vec3(0.0);
}
#endif
