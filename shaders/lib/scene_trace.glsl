#ifndef AA_SCENE_TRACE
#define AA_SCENE_TRACE
#include "/lib/light_space.glsl"
#include "/lib/voxel_trace.glsl"
#if defined(AA_VOXELS) || defined(AA_LIGHT_SPACE)
bool traceSceneFallback(vec3 origin,vec3 direction,int budget,out vec3 radiance,out float confidence) {
    #ifdef AA_VOXELS
    return traceVoxelView(origin,direction,radiance,confidence);
    #else
    return traceLightSpace(origin,direction,budget,radiance,confidence);
    #endif
}
#endif
#endif
