#include "/lib/common.glsl"
out vec2 texcoord;
void main() {
    gl_Position=ftransform();
    #ifndef AA_NATIVE_PASS
    #ifndef AA_TARGET_FRACTION
    #define AA_TARGET_FRACTION 1.0
    #endif
    gl_Position=scaleSceneClip(gl_Position,vec2(AA_TARGET_FRACTION));
    #endif
    texcoord=gl_MultiTexCoord0.xy;
}
