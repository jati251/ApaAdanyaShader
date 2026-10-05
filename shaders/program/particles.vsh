#include "/lib/common.glsl"
out vec2 texcoord,lmcoord;
out vec4 glcolor;
out vec3 viewPos;
void main() {
    texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    lmcoord=clamp((gl_TextureMatrix[1]*gl_MultiTexCoord1).xy,0.0,1.0);
    glcolor=gl_Color;
    viewPos=(gl_ModelViewMatrix*gl_Vertex).xyz;

    #ifndef WEATHER
    // Early Culling: Cull distant non-weather particles beyond 48 blocks.
    // Distant particles are sub-pixel/negligible but consume heavy fillrate and particle lighting.
    if(dot(viewPos, viewPos) > 48.0 * 48.0) {
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
        return;
    }
    #endif

    gl_Position=gl_ProjectionMatrix*vec4(viewPos,1.0);
    gl_Position=scaleSceneClip(gl_Position,vec2(1.0));
}
