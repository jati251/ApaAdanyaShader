#include "/lib/common.glsl"
in vec4 mc_Entity;
in vec2 mc_midTexCoord;
uniform mat4 shadowModelViewInverse;
out vec2 texcoord;
out vec4 glcolor;
flat out float materialId;
void main(){
    texcoord=gl_MultiTexCoord0.xy; glcolor=gl_Color; materialId=mc_Entity.x;
    vec4 p=gl_ModelViewMatrix*gl_Vertex;
    vec3 world=(shadowModelViewInverse*p).xyz+cameraPosition;
    world+=waveOffset(world,materialId,step(texcoord.y,mc_midTexCoord.y));
    p=shadowProjection*shadowModelView*vec4(world-cameraPosition,1);
    p.xyz=distortShadow(p.xyz/p.w)*p.w; gl_Position=p;
}
