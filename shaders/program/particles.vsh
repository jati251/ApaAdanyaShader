#include "/lib/common.glsl"
#if defined(AA_SMOKE) && defined(AA_PARTICLE_PASS)
uniform sampler2D gtexture;
#endif
out vec2 texcoord,lmcoord;
out vec4 glcolor;
out vec3 viewPos;
void main() {
    texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    lmcoord=clamp((gl_TextureMatrix[1]*gl_MultiTexCoord1).xy,0.0,1.0);
    glcolor=gl_Color;
    viewPos=(gl_ModelViewMatrix*gl_Vertex).xyz;

    #if defined(AA_SMOKE) && defined(AA_PARTICLE_PASS)
    // AA Smoke Bridge tags only transparent sprite corners. Step inward using
    // Minecraft 26.3's quad order, so an adjacent atlas sprite is never sampled.
    const vec2 inward[4]=vec2[4](vec2(-.5,-.5),vec2(-.5,.5),vec2(.5,.5),vec2(.5,-.5));
    ivec2 size=textureSize(gtexture,0);
    ivec2 corner=clamp(ivec2(floor(texcoord*vec2(size)+inward[gl_VertexID&3])),ivec2(0),size-1);
    vec4 tag=texelFetch(gtexture,corner,0);
    // A one-byte alpha preserves the tag through transparent-color cleanup.
    // Pure green survives sRGB decoding and premultiplied-alpha uploads alike.
    bool marker=tag.a<=.0041 && tag.g>0.0 && tag.r==0.0 && tag.b==0.0;
    bool legacy=tag.a==0.0 && (all(lessThan(abs(tag.rgb-vec3(19,211,83)/255.0),vec3(.002)))
        || all(lessThan(abs(tag.rgb-srgbToLinear(vec3(19,211,83)/255.0)),vec3(.002))));
    if(marker || legacy) {
        gl_Position=vec4(2,2,2,1);
        return;
    }
    #endif
    gl_Position=gl_ProjectionMatrix*vec4(viewPos,1.0);
    gl_Position=scaleSceneClip(gl_Position,vec2(1.0));
}
