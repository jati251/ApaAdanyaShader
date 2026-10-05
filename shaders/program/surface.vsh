#include "/lib/common.glsl"
in vec4 mc_Entity;
in vec4 at_tangent;
in vec2 mc_midTexCoord;
out vec2 texcoord, lmcoord;
out vec4 glcolor;
out vec3 viewNormal, viewPos, worldPos;
out vec4 tangent;
flat out float materialId;
#if defined(POM) && defined(TERRAIN) && defined(RESOURCE_NORMALS)
flat out vec4 atlasBounds;
#endif
void main() {
    texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    #if defined(POM) && defined(TERRAIN) && defined(RESOURCE_NORMALS)
    vec2 mid=(gl_TextureMatrix[0]*vec4(mc_midTexCoord,0.0,1.0)).xy;
    vec2 halfSize=abs(texcoord-mid);
    atlasBounds=vec4(mid-halfSize,mid+halfSize);
    #endif
    lmcoord=(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy;
    glcolor=gl_Color;
    viewNormal=normalize(gl_NormalMatrix*gl_Normal);
    tangent=vec4(normalize(gl_NormalMatrix*at_tangent.xyz),at_tangent.w);
    viewPos=(gl_ModelViewMatrix*gl_Vertex).xyz;
    worldPos=(gbufferModelViewInverse*vec4(viewPos,1.0)).xyz+cameraPosition;
    materialId=0.0;
    #if defined(TERRAIN) || defined(WATER) || defined(HAND) || defined(ENTITY)
    materialId=mc_Entity.x;
    #ifdef WAVING_FOLIAGE
    if(materialId>1000.5 && materialId<1002.5){
        vec3 offset=waveOffset(worldPos,materialId,step(texcoord.y,mc_midTexCoord.y));
        worldPos+=offset; viewPos+=mat3(gbufferModelView)*offset;
    }
    #endif
    #endif
    gl_Position=gl_ProjectionMatrix*vec4(viewPos,1.0);
    gl_Position=scaleSceneClip(gl_Position,vec2(1.0));
}
