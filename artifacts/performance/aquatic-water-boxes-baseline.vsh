#version 330 compatibility
#ifdef MC_GL_ARB_shader_image_load_store
#extension GL_ARB_shader_image_load_store : enable
#endif
#define AA_VOXEL_WRITER
#include "/lib/common.glsl"
#include "/lib/fire.glsl"
in vec4 mc_Entity;
in vec2 mc_midTexCoord;
uniform mat4 shadowModelViewInverse;
#if defined(AA_VOXELS) && defined(AA_VOXEL_WRITER)
in vec4 at_midBlock;
uniform sampler2D gtexture;
layout(r32ui) uniform uimage3D aaVoxelImage;
#include "/lib/voxel_data.glsl"
#endif
out vec2 texcoord;
out vec4 glcolor;
flat out float materialId;
#ifdef AA_LIGHT_SPACE
out vec3 bounceNormal;
#endif
void main(){
    #ifdef SHADOWS
    texcoord=gl_MultiTexCoord0.xy; glcolor=gl_Color; materialId=mc_Entity.x;
    #ifdef AA_LIGHT_SPACE
    bounceNormal=normalize(mat3(shadowModelViewInverse)*(gl_NormalMatrix*gl_Normal));
    #endif

    // Early Culling 1: Water (materialId 1003) does not cast shadows.
    // Clipping at the vertex stage prevents triangle rasterization entirely.
    if(materialId > 1002.5 && materialId < 1003.5) {
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
        return;
    }

    vec4 p=gl_ModelViewMatrix*gl_Vertex;
    vec3 relWorld=(shadowModelViewInverse*p).xyz;
    #if defined(AA_VOXELS) && defined(AA_VOXEL_WRITER)
    // Vertex atomics capture submitted terrain even when it is hidden in the
    // shadow depth map. No fragment depth test or screen visibility is involved.
    if(abs(materialId-1001.0)>0.5 && abs(materialId-1003.0)>0.5) {
        ivec3 cell=ivec3(floor(relWorld+cameraPosition+at_midBlock.xyz/64.0-voxelGridOrigin()));
        if(voxelInside(cell)) {
            vec3 albedo=srgbToLinear(textureLod(gtexture,mc_midTexCoord,0.0).rgb*glcolor.rgb);
            vec3 normal=normalize(mat3(shadowModelViewInverse)*(gl_NormalMatrix*gl_Normal));
            float emission=abs(materialId-1004.0)<0.5?15.0:0.0;
            if(abs(materialId-1008.0)<0.5){
                albedo=lavaRadiance(textureLod(gtexture,mc_midTexCoord,0.0).rgb)/4.0;
                emission=15.0;
            }
            if(abs(materialId-1006.0)<0.5 || abs(materialId-1007.0)<0.5
                || abs(materialId-1009.0)<0.5 || abs(materialId-1010.0)<0.5){
                bool soul=abs(materialId-1007.0)<0.5 || abs(materialId-1010.0)<0.5;
                albedo=(soul?vec3(0.16,0.85,1.4):vec3(1.65,0.62,0.13))/4.0;
                emission=15.0;
            }
            #ifdef IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE
            emission=max(emission,at_midBlock.w);
            #endif
            imageAtomicMax(aaVoxelImage,cell,packVoxel(albedo,emission,normal));
        }
    }
    #endif

    // Preserve triangle geometry across the shadow-distance boundary. Moving
    // individual vertices to a clip point stretches partially culled triangles.
    // Iris culls shadow casters; shadowVisibility handles receiver distance.

    #ifdef WAVING_FOLIAGE
    if(materialId > 1000.5 && materialId < 1002.5) {
        vec3 world=relWorld+cameraPosition;
        world+=waveOffset(world,materialId,step(texcoord.y,mc_midTexCoord.y));
        p=shadowProjection*(shadowModelView*vec4(world-cameraPosition,1.0));
    } else {
        p=shadowProjection*p;
    }
    #else
    p=shadowProjection*p;
    #endif
    p.xyz=distortShadow(p.xyz/p.w)*p.w; gl_Position=p;
    #else
    gl_Position=vec4(2.0,2.0,2.0,1.0); // Outside NDC: clipped instantly before rasterization
    #endif
}
