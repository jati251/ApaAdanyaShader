#ifndef AA_SCENE_TRACE
#define AA_SCENE_TRACE
#include "/lib/light_space.glsl"
#ifdef AA_LIGHT_SPACE
bool traceSceneFallback(vec3 origin,vec3 direction,int budget,out vec3 radiance,out float confidence) {
    return traceLightSpace(origin,direction,budget,radiance,confidence);
}
bool traceSceneIndirect(vec3 origin,vec3 direction,int budget,float radius,out vec3 radiance,out float confidence) {
    radiance=vec3(0.0);confidence=0.0;
    return traceLightSpaceRange(origin,direction,min(budget,24),radius,radiance,confidence);
}
#endif
#endif
