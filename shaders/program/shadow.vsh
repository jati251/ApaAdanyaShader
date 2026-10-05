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
    vec4 p=gl_ModelViewMatrix*gl_Vertex;
    vec3 world=(shadowModelViewInverse*p).xyz+cameraPosition;
    #ifdef WAVING_FOLIAGE
    world+=waveOffset(world,materialId,step(texcoord.y,mc_midTexCoord.y));
    #endif
    p=shadowProjection*(shadowModelView*vec4(world-cameraPosition,1.0));
    p.xyz=distortShadow(p.xyz/p.w)*p.w; gl_Position=p;
    #else
    gl_Position=vec4(2.0,2.0,2.0,1.0); // Outside NDC: clipped instantly before rasterization
    #endif
}
