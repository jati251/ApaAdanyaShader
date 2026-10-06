#include "/lib/common.glsl"
in vec4 mc_Entity;
in vec2 mc_midTexCoord;
uniform mat4 shadowModelViewInverse;
out vec2 texcoord;
out vec4 glcolor;
flat out float materialId;
void main(){
    #ifdef SHADOWS
    texcoord=gl_MultiTexCoord0.xy; glcolor=gl_Color; materialId=mc_Entity.x;

    // Early Culling 1: Water (materialId 1003) does not cast shadows.
    // Clipping at the vertex stage prevents triangle rasterization entirely.
    if(materialId > 1002.5 && materialId < 1003.5) {
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
        return;
    }

    vec4 p=gl_ModelViewMatrix*gl_Vertex;
    vec3 relWorld=(shadowModelViewInverse*p).xyz;

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
